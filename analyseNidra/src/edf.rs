use anyhow::{Context, Result, bail};
use rayon::prelude::*;
use std::collections::HashMap;
use std::fs::File;
use std::io::{Read, Seek, SeekFrom};
use std::path::Path;

#[derive(Debug, Clone)]
struct SignalHeader {
    label: String,
    physical_min: f64,
    physical_max: f64,
    digital_min: f64,
    digital_max: f64,
    samples_per_record: usize,
}

#[derive(Debug)]
pub struct EdfData {
    pub sfreq: f64,
    pub duration_seconds: f64,
    pub channels: Vec<String>,
    pub data_uv: Vec<Vec<f64>>,
}

fn text(bytes: &[u8]) -> String {
    String::from_utf8_lossy(bytes).trim().to_string()
}

fn parse_f64(bytes: &[u8], field: &str) -> Result<f64> {
    text(bytes)
        .parse()
        .with_context(|| format!("parsing EDF {field}"))
}

fn parse_usize(bytes: &[u8], field: &str) -> Result<usize> {
    text(bytes)
        .parse()
        .with_context(|| format!("parsing EDF {field}"))
}

fn read_field_matrix(file: &mut File, count: usize, width: usize) -> Result<Vec<Vec<u8>>> {
    let mut bytes = vec![0_u8; count * width];
    file.read_exact(&mut bytes)?;
    Ok(bytes.chunks_exact(width).map(<[u8]>::to_vec).collect())
}

fn canonical_channel(label: &str) -> String {
    let mut name = label.replace("EEG ", "").replace("-Ref", "");
    if let Some(rest) = name.strip_prefix("POL ") {
        name = rest.to_string();
    }
    if name.eq_ignore_ascii_case("A1") {
        "M1".into()
    } else if name.eq_ignore_ascii_case("A2") {
        "M2".into()
    } else {
        name
    }
}

fn load_custom_channel_map(path: &Path) -> HashMap<usize, String> {
    let mut map = HashMap::new();
    let config_path = path.with_extension("config.json");
    if let Ok(content) = std::fs::read_to_string(&config_path) {
        if let Ok(serde_json::Value::Array(arr)) =
            serde_json::from_str::<serde_json::Value>(&content)
        {
            if arr.len() >= 2 {
                if let Some(channels_list) = arr[1].as_array() {
                    for c in channels_list {
                        let is_derived =
                            c.get("derived").and_then(|v| v.as_bool()).unwrap_or(false);
                        if is_derived {
                            continue;
                        }
                        if let (Some(name), Some(idx)) = (
                            c.get("Channel_name").and_then(|v| v.as_str()),
                            c.get("sourceIndex").and_then(|v| v.as_u64()),
                        ) {
                            map.insert(idx as usize, name.to_string());
                        }
                    }
                }
            }
        }
    }
    map
}

pub fn read_selected(path: &Path, requested: &[String]) -> Result<EdfData> {
    if requested.is_empty() {
        bail!("at least one EDF channel must be selected");
    }
    let mut file = File::open(path).with_context(|| format!("opening {}", path.display()))?;
    let mut fixed = [0_u8; 256];
    file.read_exact(&mut fixed)?;
    let header_bytes = parse_usize(&fixed[184..192], "header bytes")?;
    let num_records = parse_usize(&fixed[236..244], "number of records")?;
    let record_duration = parse_f64(&fixed[244..252], "record duration")?;
    let num_signals = parse_usize(&fixed[252..256], "number of signals")?;

    let labels = read_field_matrix(&mut file, num_signals, 16)?;
    let _transducer = read_field_matrix(&mut file, num_signals, 80)?;
    let _units = read_field_matrix(&mut file, num_signals, 8)?;
    let physical_min = read_field_matrix(&mut file, num_signals, 8)?;
    let physical_max = read_field_matrix(&mut file, num_signals, 8)?;
    let digital_min = read_field_matrix(&mut file, num_signals, 8)?;
    let digital_max = read_field_matrix(&mut file, num_signals, 8)?;
    let _prefilter = read_field_matrix(&mut file, num_signals, 80)?;
    let samples_per_record = read_field_matrix(&mut file, num_signals, 8)?;
    let _reserved = read_field_matrix(&mut file, num_signals, 32)?;
    file.seek(SeekFrom::Start(header_bytes as u64))?;

    let custom_map = load_custom_channel_map(path);

    let mut headers = Vec::with_capacity(num_signals);
    for index in 0..num_signals {
        let label = if let Some(custom_name) = custom_map.get(&index) {
            canonical_channel(custom_name)
        } else {
            canonical_channel(&text(&labels[index]))
        };
        headers.push(SignalHeader {
            label,
            physical_min: parse_f64(&physical_min[index], "physical minimum")?,
            physical_max: parse_f64(&physical_max[index], "physical maximum")?,
            digital_min: parse_f64(&digital_min[index], "digital minimum")?,
            digital_max: parse_f64(&digital_max[index], "digital maximum")?,
            samples_per_record: parse_usize(&samples_per_record[index], "samples per record")?,
        });
    }

    let by_name: HashMap<String, usize> = headers
        .iter()
        .enumerate()
        .map(|(index, header)| (header.label.to_ascii_lowercase(), index))
        .collect();
    let selected: Vec<usize> = requested
        .iter()
        .map(|name| {
            by_name
                .get(&canonical_channel(name).to_ascii_lowercase())
                .copied()
                .with_context(|| format!("EDF channel {name} is missing"))
        })
        .collect::<Result<_>>()?;
    let selected_lookup: HashMap<usize, usize> = selected
        .iter()
        .enumerate()
        .map(|(output, &input)| (input, output))
        .collect();

    let first_spr = headers[selected[0]].samples_per_record;
    if selected
        .iter()
        .any(|&index| headers[index].samples_per_record != first_spr)
    {
        bail!("selected EDF channels do not share one sampling frequency");
    }
    let sfreq = first_spr as f64 / record_duration;
    let mut data = requested
        .iter()
        .map(|_| Vec::with_capacity(num_records * first_spr))
        .collect::<Vec<_>>();
    let max_spr = headers
        .iter()
        .map(|header| header.samples_per_record)
        .max()
        .unwrap_or(0);
    let mut bytes = vec![0_u8; max_spr * 2];

    for _ in 0..num_records {
        for (signal_index, header) in headers.iter().enumerate() {
            let byte_count = header.samples_per_record * 2;
            file.read_exact(&mut bytes[..byte_count])?;
            let Some(&output_index) = selected_lookup.get(&signal_index) else {
                continue;
            };
            let scale = (header.physical_max - header.physical_min)
                / (header.digital_max - header.digital_min);
            let offset = header.physical_min - header.digital_min * scale;
            data[output_index].extend(
                bytes[..byte_count]
                    .chunks_exact(2)
                    .map(|pair| i16::from_le_bytes([pair[0], pair[1]]) as f64 * scale + offset),
            );
        }
    }
    data.par_iter_mut()
        .for_each(|channel| channel.shrink_to_fit());
    Ok(EdfData {
        sfreq,
        duration_seconds: num_records as f64 * record_duration,
        channels: requested.to_vec(),
        data_uv: data,
    })
}
