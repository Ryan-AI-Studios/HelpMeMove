//! Check one synthetic exercise directory. Success prints `ok <count>`.

use std::io::{self, Write};
use std::path::PathBuf;
use std::process::ExitCode;

use helpmemove_content::{SyntheticOnly, link_library, load_exercise_dir};

fn main() -> ExitCode {
    let mut args = std::env::args_os().skip(1);
    let Some(dir) = args.next() else {
        return ExitCode::from(2);
    };
    if args.next().is_some() {
        return ExitCode::from(2);
    }
    match load_exercise_dir(&PathBuf::from(dir), SyntheticOnly).and_then(link_library) {
        Ok(library) => {
            if write_line(&format!("ok {}", library.len())) {
                ExitCode::SUCCESS
            } else {
                ExitCode::from(1)
            }
        }
        Err(error) => {
            let _ = write_line(&format!("error {error}"));
            ExitCode::from(1)
        }
    }
}

fn write_line(message: &str) -> bool {
    let mut stdout = io::stdout();
    writeln!(stdout, "{message}").is_ok()
}
