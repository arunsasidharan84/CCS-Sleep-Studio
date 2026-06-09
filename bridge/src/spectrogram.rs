use rustfft::{FftPlanner, num_complex::Complex};
use rayon::prelude::*;

#[repr(C)]
pub struct SpectrogramResult {
    pub power: *mut f32,
    pub power_len: i32,
    pub freqs: *mut f32,
    pub freqs_len: i32,
    pub n_epochs: i32,
    pub n_freqs: i32,
}

pub fn welch_psd(
    signal: &[f32],
    srate: f32,
    win_len_sec: f32,
    step_sec: f32,
) -> (Vec<f32>, Vec<f32>) {
    let mut win_samples = (win_len_sec * srate).round() as usize;
    let mut step_samples = (step_sec * srate).round() as usize;

    if win_samples > signal.len() {
        win_samples = signal.len();
        step_samples = win_samples / 2;
    }
    if win_samples < 4 {
        win_samples = 4;
        step_samples = 2;
    }

    let nfft = win_samples.next_power_of_two();
    let nfreqs = nfft / 2 + 1;

    // Hann window
    let mut window = vec![0.0f32; win_samples];
    let mut win_norm = 0.0f32;
    for i in 0..win_samples {
        let w = 0.5f32 * (1.0f32 - ((2.0f32 * std::f32::consts::PI * i as f32) / (win_samples as f32 - 1.0f32)).cos());
        window[i] = w;
        win_norm += w * w;
    }

    let mut psd = vec![0.0f32; nfreqs];
    let mut n_windows = 0;

    let mut planner = FftPlanner::new();
    let fft = planner.plan_fft_forward(nfft);

    let mut start = 0;
    while start + win_samples <= signal.len() {
        let mut buffer = vec![Complex::new(0.0f32, 0.0f32); nfft];
        for i in 0..win_samples {
            buffer[i] = Complex::new(signal[start + i] * window[i], 0.0f32);
        }

        fft.process(&mut buffer);

        // Accumulate |FFT|² for one-sided PSD estimation
        psd[0] += buffer[0].norm_sqr();
        for i in 1..nfreqs - 1 {
            psd[i] += 2.0f32 * buffer[i].norm_sqr();
        }
        psd[nfreqs - 1] += buffer[nfreqs - 1].norm_sqr();

        n_windows += 1;
        start += step_samples;
    }

    let freqs: Vec<f32> = (0..nfreqs)
        .map(|i| i as f32 * srate / nfft as f32)
        .collect();

    if n_windows == 0 {
        return (vec![0.0f32; nfreqs], freqs);
    }

    let scale = 1.0f32 / (n_windows as f32 * srate * win_norm);
    for val in psd.iter_mut() {
        *val *= scale;
    }

    (psd, freqs)
}

pub fn compute_spectrogram_impl(
    signal: &[f32],
    srate: f32,
    epoch_seconds: i32,
    extension_seconds: i32,
) -> (Vec<f32>, Vec<f32>, i32, i32) {
    let total_samples = signal.len();
    let epoch_samples = (epoch_seconds as f32 * srate).round() as usize;
    let extension_samples = (extension_seconds as f32 * srate).round() as usize;
    let n_epochs = (total_samples as f32 / epoch_samples as f32).ceil() as usize;

    if n_epochs == 0 {
        return (Vec::new(), Vec::new(), 0, 0);
    }

    // Determine target win_samples & nfreqs beforehand
    let mut win_samples = (4.0f32 * srate).round() as usize;
    let test_slice_len = usize::min(total_samples, epoch_samples + 2 * extension_samples);
    if win_samples > test_slice_len {
        win_samples = test_slice_len;
    }
    if win_samples < 4 {
        win_samples = 4;
    }
    let nfft = win_samples.next_power_of_two();
    let nfreqs = nfft / 2 + 1;

    let mut power = vec![0.0f32; n_epochs * nfreqs];
    let mut freqs = vec![0.0f32; nfreqs];
    for i in 0..nfreqs {
        freqs[i] = i as f32 * srate / nfft as f32;
    }

    // Compute epochs in parallel using rayon
    power
        .par_chunks_mut(nfreqs)
        .enumerate()
        .for_each(|(epoch_idx, row)| {
            let start = (epoch_idx * epoch_samples).saturating_sub(extension_samples);
            let end = usize::min(total_samples, (epoch_idx + 1) * epoch_samples + extension_samples);
            
            if start < end {
                let slice = &signal[start..end];
                let (psd, _) = welch_psd(slice, srate, 4.0f32, 2.0f32);
                let limit = usize::min(psd.len(), nfreqs);
                for i in 0..limit {
                    row[i] = psd[i];
                }
            }
        });

    (power, freqs, n_epochs as i32, nfreqs as i32)
}

#[no_mangle]
pub extern "C" fn sleep_eeg_compute_welch_spectrogram(
    signal: *const f32,
    signal_len: i32,
    srate: f32,
    epoch_seconds: i32,
    extension_seconds: i32,
) -> *mut SpectrogramResult {
    if signal.is_null() || signal_len <= 0 || srate <= 0.0 {
        return std::ptr::null_mut();
    }

    let signal_slice = unsafe { std::slice::from_raw_parts(signal, signal_len as usize) };
    let (mut power, mut freqs, n_epochs, n_freqs) = compute_spectrogram_impl(
        signal_slice,
        srate,
        epoch_seconds,
        extension_seconds,
    );

    let power_len = power.len() as i32;
    let freqs_len = freqs.len() as i32;

    let result = Box::new(SpectrogramResult {
        power: power.leak().as_mut_ptr(),
        power_len,
        freqs: freqs.leak().as_mut_ptr(),
        freqs_len,
        n_epochs,
        n_freqs,
    });

    Box::into_raw(result)
}

#[no_mangle]
pub extern "C" fn sleep_eeg_free_spectrogram(result: *mut SpectrogramResult) {
    if result.is_null() {
        return;
    }
    unsafe {
        let res_box = Box::from_raw(result);
        if !res_box.power.is_null() && res_box.power_len > 0 {
            let _ = Vec::from_raw_parts(
                res_box.power,
                res_box.power_len as usize,
                res_box.power_len as usize,
            );
        }
        if !res_box.freqs.is_null() && res_box.freqs_len > 0 {
            let _ = Vec::from_raw_parts(
                res_box.freqs,
                res_box.freqs_len as usize,
                res_box.freqs_len as usize,
            );
        }
    }
}
