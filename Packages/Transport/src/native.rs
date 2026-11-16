use std::{
    ffi::{CStr, CString, c_char},
    sync::{
        Mutex,
        atomic::{AtomicBool, Ordering},
    },
};
type Callback = extern "C" fn(*const c_char);
static CALLBACK: Mutex<Option<Callback>> = Mutex::new(None);
static ACTIVE: AtomicBool = AtomicBool::new(false);
static CANCELLED: AtomicBool = AtomicBool::new(false);

pub(crate) fn cancelled() -> bool {
    CANCELLED.load(Ordering::Relaxed)
}
pub(crate) fn deliver(value: &serde_json::Value) {
    if let Ok(callback) = CALLBACK.lock()
        && let Some(callback) = *callback
        && let Ok(text) = CString::new(value.to_string())
    {
        callback(text.as_ptr());
    }
}

/// Signal the currently running native experiment to release its sockets.
#[unsafe(no_mangle)]
pub extern "C" fn trunkline_p2p_stop() {
    CANCELLED.store(true, Ordering::Relaxed);
}

/// Prepare on the UI thread before scheduling the worker. A later stop must
/// not be erased by a delayed worker starting in the background.
#[unsafe(no_mangle)]
pub extern "C" fn trunkline_p2p_prepare() {
    if !ACTIVE.load(Ordering::SeqCst) {
        CANCELLED.store(false, Ordering::Relaxed);
    }
}

/// Runs on a caller-owned background thread; never on the iOS UI thread.
/// # Safety
/// Both pointers must be valid NUL-terminated UTF-8 strings for the call's duration.
/// The callback must remain callable until this function returns and copy its input.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn trunkline_p2p_run(
    config: *const c_char,
    helper: *const c_char,
    callback: Option<Callback>,
) -> i32 {
    unsafe { run_native(config, helper, callback, false) }
}

/// Runs the direct application bridge on a background thread.
/// # Safety
/// Strings and callback must remain valid until this blocking call returns.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn trunkline_p2p_session(
    config: *const c_char,
    helper: *const c_char,
    callback: Option<Callback>,
) -> i32 {
    unsafe { run_native(config, helper, callback, true) }
}
unsafe fn run_native(
    config: *const c_char,
    helper: *const c_char,
    callback: Option<Callback>,
    session: bool,
) -> i32 {
    if config.is_null() || helper.is_null() {
        return 1;
    }
    if ACTIVE.swap(true, Ordering::SeqCst) {
        return 3;
    }
    *CALLBACK.lock().unwrap() = callback;
    let result = std::panic::catch_unwind(|| -> anyhow::Result<bool> {
        let config = unsafe { CStr::from_ptr(config) }.to_str()?;
        let helper = unsafe { CStr::from_ptr(helper) }.to_str()?;
        let runtime = tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .enable_all()
            .build()?;
        if session {
            return runtime.block_on(crate::session::run(
                serde_json::from_str(config)?,
                helper.parse()?,
                false,
            ));
        }
        let args = crate::runner::Args {
            command: crate::runner::Command::Probe {
                config: config.into(),
                helper: helper.parse()?,
                mode: crate::runner::Mode::Dial,
                seconds: 110,
            },
        };
        runtime.block_on(crate::runner::run(args))
    });
    let code = match result {
        Ok(Ok(true)) => 0,
        Ok(Ok(false)) => 2,
        Ok(Err(error)) => {
            deliver(
                &serde_json::json!({"event":"native_error","details":{"error":error.to_string()}}),
            );
            1
        }
        Err(_) => {
            deliver(
                &serde_json::json!({"event":"native_error","details":{"error":"Native experiment stopped after an internal error"}}),
            );
            4
        }
    };
    *CALLBACK.lock().unwrap() = None;
    ACTIVE.store(false, Ordering::SeqCst);
    code
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn ffi_rejects_null_configuration_without_starting_a_runtime() {
        assert_eq!(
            unsafe { trunkline_p2p_run(std::ptr::null(), std::ptr::null(), None) },
            1
        );
    }

    #[test]
    fn stop_requested_before_worker_start_is_not_erased() {
        trunkline_p2p_prepare();
        trunkline_p2p_stop();
        let config = CString::new("/nonexistent-trunkline-probe-config.json").unwrap();
        let helper = CString::new(format!(
            "/ip4/127.0.0.1/tcp/9/p2p/{}",
            libp2p::PeerId::random()
        ))
        .unwrap();
        assert_eq!(
            unsafe { trunkline_p2p_run(config.as_ptr(), helper.as_ptr(), None) },
            1
        );
        assert!(
            cancelled(),
            "Worker start erased a foreground/background cancellation"
        );
        trunkline_p2p_prepare();
    }
}
