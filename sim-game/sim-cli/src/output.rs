//! Where command output goes. In the plain prompt it's printed. In the
//! inspector it's captured and shown in the console panel.

use std::sync::Mutex;

static SINK: Mutex<Option<Vec<String>>> = Mutex::new(None);

/// Print `text`, or capture it if capturing is on.
pub fn emit(text: String) {
    let mut sink = SINK.lock().unwrap();
    match sink.as_mut() {
        Some(buf) => buf.extend(text.lines().map(String::from)),
        None => println!("{}", text.trim_end_matches('\n')),
    }
}

pub fn capture(on: bool) {
    *SINK.lock().unwrap() = on.then(Vec::new);
}

/// Take everything captured since the last drain.
pub fn drain() -> Vec<String> {
    SINK.lock()
        .unwrap()
        .as_mut()
        .map(std::mem::take)
        .unwrap_or_default()
}

macro_rules! out {
    ($($arg:tt)*) => { $crate::output::emit(format!($($arg)*)) };
}
pub(crate) use out;
