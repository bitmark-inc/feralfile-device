use std::collections::HashMap;
use std::fs::File;
use std::io::{BufRead, BufReader, BufWriter, Write};
use std::path::Path;
use std::sync::Mutex;

pub struct Cache {
    data: Mutex<HashMap<String, String>>,
}

pub const TOPIC_ID: &str = "topic_id";
pub const LOCATION_ID: &str = "location_id";

impl Cache {
    pub fn new(filepath: &str) -> Self {
        let mut data = HashMap::new();
        if Path::new(filepath).exists() {
            let file = File::open(filepath).unwrap();
            let reader = BufReader::new(file);
            for line in reader.lines() {
                if let Ok(line) = line {
                    if line.trim().is_empty() {
                        continue;
                    }
                    let (key, value) = line.split_once("=").unwrap();
                    data.insert(key.to_string(), value.to_string());
                }
            }
        }
        Self {
            data: Mutex::new(data),
        }
    }

    pub fn set(&self, key: &str, value: &str) {
        self.data
            .lock()
            .unwrap()
            .insert(key.to_string(), value.to_string());
    }

    pub fn get(&self, key: &str) -> Option<String> {
        self.data.lock().unwrap().get(key).cloned()
    }

    pub fn save(&self, filepath: &str) {
        let file = File::create(filepath).unwrap();
        let mut writer = BufWriter::new(file);
        for (key, value) in self.data.lock().unwrap().iter() {
            writer
                .write_all(format!("{}={}\n", key, value).as_bytes())
                .unwrap();
        }
    }
}
