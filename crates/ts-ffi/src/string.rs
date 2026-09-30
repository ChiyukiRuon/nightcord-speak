//! Handing strings across the C ABI.
//!
//! Every string this crate returns is heap-allocated and must be handed back to
//! [`free_c_string`]. Every string it accepts is borrowed for the duration of
//! the call and must be NUL-terminated UTF-8.

use std::ffi::{CStr, CString, c_char};

/// Moves `value` onto the heap as a NUL-terminated string for the caller.
///
/// The caller owns the result and must pass it to [`free_c_string`].
///
/// All output here is JSON from `serde_json`, which escapes control characters
/// including `\0`, so the text can never contain an interior NUL and this
/// cannot fail in practice. An empty string is returned rather than a null
/// pointer if it somehow does, so a caller cannot be handed `NULL` to
/// dereference.
#[must_use]
pub(crate) fn into_c_string(value: impl Into<String>) -> *mut c_char {
    let value = value.into();
    match CString::new(value) {
        Ok(text) => text.into_raw(),
        Err(error) => {
            // Reaching here means an interior NUL survived serialisation, which
            // would be a bug in this crate rather than in the caller's data.
            tracing::error!("a string crossing the FFI contained an interior NUL");
            let salvaged = error.into_vec();
            CString::new(
                salvaged
                    .into_iter()
                    .filter(|b| *b != 0)
                    .collect::<Vec<u8>>(),
            )
            .unwrap_or_default()
            .into_raw()
        }
    }
}

/// Borrows a string passed in from C.
///
/// # Safety
///
/// `ptr` must be null or a valid NUL-terminated string that stays alive for the
/// duration of the call.
pub(crate) unsafe fn from_c_str(ptr: *const c_char) -> Option<String> {
    if ptr.is_null() {
        return None;
    }
    // Safety: the caller guarantees a valid NUL-terminated string.
    let text = unsafe { CStr::from_ptr(ptr) };
    Some(text.to_string_lossy().into_owned())
}

/// Reclaims a string previously returned by [`into_c_string`].
///
/// # Safety
///
/// `ptr` must be null, or a pointer returned by [`into_c_string`] that has not
/// already been freed. Freeing anything else, or freeing the same pointer
/// twice, is undefined behaviour.
pub(crate) unsafe fn free_c_string(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    // Safety: the caller guarantees this came from `CString::into_raw` and has
    // not been freed.
    drop(unsafe { CString::from_raw(ptr) });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_string_survives_the_round_trip() {
        let raw = into_c_string("hello");
        // Safety: `raw` came from `into_c_string` and is freed exactly once.
        unsafe {
            assert_eq!(from_c_str(raw).as_deref(), Some("hello"));
            free_c_string(raw);
        }
    }

    #[test]
    fn a_null_pointer_reads_as_none() {
        // Safety: a null pointer is explicitly allowed.
        unsafe {
            assert_eq!(from_c_str(std::ptr::null()), None);
        }
    }

    #[test]
    fn freeing_null_is_harmless() {
        // Safety: freeing null is explicitly allowed and must be a no-op, since
        // a Dart caller may free a pointer it never received.
        unsafe { free_c_string(std::ptr::null_mut()) };
    }

    #[test]
    fn json_never_produces_a_pointer_we_cannot_free() {
        // Serialised JSON escapes control characters, so even data that would
        // break a naive `CString::new` comes back intact.
        let json = serde_json::to_string("a\u{0}b").unwrap();
        assert!(!json.contains('\0'), "serde escaped the NUL: {json:?}");

        let raw = into_c_string(json.clone());
        // Safety: as above.
        unsafe {
            assert_eq!(from_c_str(raw).as_deref(), Some(json.as_str()));
            free_c_string(raw);
        }
    }
}
