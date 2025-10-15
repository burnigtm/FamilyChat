//! FamilyChat crypto FFI surface.
//!
//! This crate intentionally exposes JSON-encoded helpers over a C-compatible
//! boundary so the Flutter client can call into the Signal-inspired primitives
//! via `flutter_rust_bridge`. The current implementation ships with secure
//! randomness and type-safe serialization but leaves the actual Signal protocol
//! wiring as a follow-up milestone.

mod error;
mod groups;
mod identity;
mod message;
mod prekeys;

pub use error::{CryptoError, CryptoResult};
pub use groups::GroupSenderKey;
pub use identity::IdentityBundle;
pub use message::{EncryptedEnvelope, MessagePayload, MessageType};
pub use prekeys::{PreKeyBundle, PreKeyRecord};

use ffi_support::{define_string_destructor, ErrorCode, ExternError, FfiStr, rust_string_to_c};
use std::os::raw::c_char;

define_string_destructor!(fc_string_free);

#[no_mangle]
pub extern "C" fn fc_generate_identity(out: &mut ExternError) -> *mut c_char {
    match identity::generate_identity_bundle() {
        Ok(bundle) => to_json(bundle, out),
        Err(err) => set_error(err, out),
    }
}

#[no_mangle]
pub extern "C" fn fc_create_prekeys(count: u32, out: &mut ExternError) -> *mut c_char {
    match prekeys::generate_bundle(count) {
        Ok(bundle) => to_json(bundle, out),
        Err(err) => set_error(err, out),
    }
}

#[no_mangle]
pub extern "C" fn fc_encrypt_message(payload_json: FfiStr<'_>, out: &mut ExternError) -> *mut c_char {
    match serde_json::from_str::<MessagePayload>(payload_json.as_str()) {
        Ok(payload) => match message::encrypt_message(payload) {
            Ok(envelope) => to_json(envelope, out),
            Err(err) => set_error(err, out),
        },
        Err(err) => set_error(err.into(), out),
    }
}

#[no_mangle]
pub extern "C" fn fc_decrypt_message(envelope_json: FfiStr<'_>, out: &mut ExternError) -> *mut c_char {
    match serde_json::from_str::<message::EncryptedEnvelope>(envelope_json.as_str()) {
        Ok(envelope) => match message::decrypt_message(envelope) {
            Ok(plaintext) => to_json(plaintext, out),
            Err(err) => set_error(err, out),
        },
        Err(err) => set_error(err.into(), out),
    }
}

#[no_mangle]
pub extern "C" fn fc_group_sender_key_init(conversation_id: FfiStr<'_>, out: &mut ExternError) -> *mut c_char {
    match groups::initialize_sender_key(conversation_id.as_str()) {
        Ok(key) => to_json(key, out),
        Err(err) => set_error(err, out),
    }
}

#[no_mangle]
pub extern "C" fn fc_group_sender_key_rotate(existing_json: FfiStr<'_>, out: &mut ExternError) -> *mut c_char {
    match serde_json::from_str::<groups::GroupSenderKey>(existing_json.as_str()) {
        Ok(existing) => match groups::rotate_sender_key(&existing) {
            Ok(rotated) => to_json(rotated, out),
            Err(err) => set_error(err, out),
        },
        Err(err) => set_error(err.into(), out),
    }
}

fn to_json<T: serde::Serialize>(value: T, out: &mut ExternError) -> *mut c_char {
    match serde_json::to_string(&value) {
        Ok(json) => {
            *out = ExternError::success();
            rust_string_to_c(json)
        }
        Err(err) => set_error(err.into(), out),
    }
}

fn set_error(err: CryptoError, out: &mut ExternError) -> *mut c_char {
    *out = ExternError::new_error(ErrorCode::new(1), err.to_string());
    std::ptr::null_mut()
}
