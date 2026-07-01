use crate::pipeline::LoadedRecording;
use crate::signal::{analytic_signal, scipy_filtfilt_fir};
use rayon::prelude::*;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::f64::consts::PI;

#[derive(Deserialize)]
struct FilterDefinition {
    low: f64,
    high: f64,
    order: usize,
    coefficients: Vec<f64>,
}

#[derive(Deserialize)]
struct FilterBank {
    phase: Vec<FilterDefinition>,
    amplitude: Vec<FilterDefinition>,
}

#[derive(Debug, Serialize)]
pub struct PacChannelResult {
    pub maximum: f64,
    pub amplitude_frequency: f64,
    pub phase_frequency: f64,
    pub mean_over_epochs: Vec<Vec<f64>>,
}

#[derive(Debug, Serialize)]
pub struct DebugSeries {
    pub first: Vec<f64>,
    pub mid: Vec<f64>,
    pub last: Vec<f64>,
    pub sum: f64,
    pub sumsq: f64,
    pub min: f64,
    pub max: f64,
}

fn debug_series(values: &[f64]) -> DebugSeries {
    DebugSeries {
        first: values[..10].to_vec(),
        mid: values[1000..1010].to_vec(),
        last: values[values.len() - 10..].to_vec(),
        sum: values.iter().sum(),
        sumsq: values.iter().map(|value| value * value).sum(),
        min: values.iter().copied().fold(f64::INFINITY, f64::min),
        max: values.iter().copied().fold(f64::NEG_INFINITY, f64::max),
    }
}

fn phase_bins(phase: &[f64]) -> Vec<usize> {
    let bins = 18;
    phase
        .iter()
        .map(|&phase_value| {
            let mut bin = (((phase_value + PI) / (2.0 * PI) * bins as f64).floor()) as isize;
            bin = bin.clamp(0, bins as isize - 1);
            bin as usize
        })
        .collect()
}

fn modulation_indices(
    phases: &[Vec<f64>],
    amplitudes: &[Vec<f64>],
    global_counts: &[usize],
) -> Vec<f64> {
    let bins = 18;
    let binned_phases = phases
        .iter()
        .map(|phase| phase_bins(phase))
        .collect::<Vec<_>>();
    binned_phases
        .iter()
        .zip(amplitudes)
        .map(|(epoch_bins, amplitude)| {
            let mut means = vec![0.0; bins];
            for (&bin, &value) in epoch_bins.iter().zip(amplitude) {
                means[bin] += value;
            }
            for (mean, &count) in means.iter_mut().zip(global_counts) {
                if count > 0 {
                    *mean /= count as f64;
                }
            }
            let total = means.iter().sum::<f64>();
            if total == 0.0 || means.iter().any(|&value| value <= 0.0) {
                return 0.0;
            }
            1.0 + means
                .iter()
                .map(|value| {
                    let probability = value / total;
                    probability * probability.ln()
                })
                .sum::<f64>()
                / (bins as f64).ln()
        })
        .collect()
}

fn channel_pac(windows: &[Vec<f64>], bank: &FilterBank) -> PacChannelResult {
    let phase_values: Vec<Vec<Vec<f64>>> = bank
        .phase
        .par_iter()
        .map(|filter| {
            windows
                .iter()
                .map(|window| {
                    let filtered = scipy_filtfilt_fir(window, &filter.coefficients, filter.order);
                    analytic_signal(&filtered)
                        .into_iter()
                        .map(|value| value.arg())
                        .collect()
                })
                .collect()
        })
        .collect();
    let amplitude_values: Vec<Vec<Vec<f64>>> = bank
        .amplitude
        .par_iter()
        .map(|filter| {
            windows
                .iter()
                .map(|window| {
                    let filtered = scipy_filtfilt_fir(window, &filter.coefficients, filter.order);
                    analytic_signal(&filtered)
                        .into_iter()
                        .map(|value| value.norm())
                        .collect()
                })
                .collect()
        })
        .collect();

    // Tensorpac's tensor implementation uses idx.sum() across every phase
    // band and epoch when averaging each phase bin.
    let mut global_counts = vec![0_usize; 18];
    for phase_band in &phase_values {
        for epoch in phase_band {
            for bin in phase_bins(epoch) {
                global_counts[bin] += 1;
            }
        }
    }
    let mut means = vec![vec![0.0; bank.phase.len()]; bank.amplitude.len()];
    for (amplitude_index, amplitudes) in amplitude_values.iter().enumerate() {
        for (phase_index, phases) in phase_values.iter().enumerate() {
            means[amplitude_index][phase_index] =
                modulation_indices(phases, amplitudes, &global_counts)
                    .into_iter()
                    .sum::<f64>()
                    / windows.len() as f64;
        }
    }
    let mut maximum = f64::NEG_INFINITY;
    let mut maximum_amplitude = 0;
    let mut maximum_phase = 0;
    for (amplitude_index, row) in means.iter().enumerate() {
        for (phase_index, &value) in row.iter().enumerate() {
            if value > maximum {
                maximum = value;
                maximum_amplitude = amplitude_index;
                maximum_phase = phase_index;
            }
        }
    }
    PacChannelResult {
        maximum,
        amplitude_frequency: (bank.amplitude[maximum_amplitude].low
            + bank.amplitude[maximum_amplitude].high)
            / 2.0,
        phase_frequency: (bank.phase[maximum_phase].low + bank.phase[maximum_phase].high) / 2.0,
        mean_over_epochs: means,
    }
}

pub fn compute(recording: &LoadedRecording) -> BTreeMap<String, PacChannelResult> {
    let bank: FilterBank =
        serde_json::from_str(include_str!("../assets/tensorpac_pac_filters_250hz.json"))
            .expect("embedded TensorPAC filter bank is valid");
    let samples_per_window = (15.0 * recording.edf.sfreq).round() as usize;
    recording
        .edf
        .channels
        .par_iter()
        .zip(recording.edf.data_uv.par_iter())
        .map(|(name, channel)| {
            let nrem: Vec<f64> = channel
                .iter()
                .zip(&recording.sample_stages)
                .filter_map(|(&value, &stage)| matches!(stage, 2 | 3).then_some(value))
                .collect();
            let windows = nrem
                .chunks_exact(samples_per_window)
                .map(<[f64]>::to_vec)
                .collect::<Vec<_>>();
            (name.clone(), channel_pac(&windows, &bank))
        })
        .collect()
}

pub fn debug_first_window(recording: &LoadedRecording) -> BTreeMap<String, DebugSeries> {
    let bank: FilterBank =
        serde_json::from_str(include_str!("../assets/tensorpac_pac_filters_250hz.json"))
            .expect("embedded TensorPAC filter bank is valid");
    let channel = &recording.edf.data_uv[0];
    let window: Vec<f64> = channel
        .iter()
        .zip(&recording.sample_stages)
        .filter_map(|(&value, &stage)| matches!(stage, 2 | 3).then_some(value))
        .take(3750)
        .collect();
    let phase_filtered =
        scipy_filtfilt_fir(&window, &bank.phase[0].coefficients, bank.phase[0].order);
    let phase = analytic_signal(&phase_filtered)
        .into_iter()
        .map(|value| value.arg())
        .collect::<Vec<_>>();
    let amplitude_filtered = scipy_filtfilt_fir(
        &window,
        &bank.amplitude[0].coefficients,
        bank.amplitude[0].order,
    );
    let amplitude = analytic_signal(&amplitude_filtered)
        .into_iter()
        .map(|value| value.norm())
        .collect::<Vec<_>>();
    BTreeMap::from([
        ("pf".into(), debug_series(&phase_filtered)),
        ("pa".into(), debug_series(&phase)),
        ("af".into(), debug_series(&amplitude_filtered)),
        ("aa".into(), debug_series(&amplitude)),
    ])
}
