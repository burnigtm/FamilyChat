use std::ffi::{CStr, CString};

use familychat_crypto::{
    fc_create_prekeys, fc_decrypt_message, fc_encrypt_message, fc_generate_identity,
    fc_group_sender_key_init, fc_group_sender_key_rotate, fc_string_free,
};
use ffi_support::{ExternError, FfiStr};
use serde_json::Value;

fn take_string(ptr: *mut std::os::raw::c_char) -> String {
    assert!(!ptr.is_null(), "null pointer returned from FFI");
    unsafe {
        let s = CStr::from_ptr(ptr).to_string_lossy().into_owned();
        fc_string_free(ptr);
        s
    }
}

fn assert_success(err: &ExternError) {
    if !err.get_code().is_success() {
        panic!(
            "ffi error: {:?}",
            err.get_message().as_opt_str().unwrap_or("unknown")
        );
    }
}

#[test]
fn ffi_identity_roundtrip() {
    let mut err = ExternError::default();
    let ptr = fc_generate_identity(&mut err);
    assert_success(&err);

    let json = take_string(ptr);
    let value: Value = serde_json::from_str(&json).expect("json");
    assert!(value.get("device_id").is_some());
    assert_eq!(value["signed_prekey"]["public_key"].as_str().unwrap().len(), 44);
}

#[test]
fn ffi_prekeys_returns_requested_amount() {
    let mut err = ExternError::default();
    let ptr = fc_create_prekeys(3, &mut err);
    assert_success(&err);

    let json = take_string(ptr);
    let value: Value = serde_json::from_str(&json).expect("json");
    assert_eq!(value["prekeys"].as_array().unwrap().len(), 3);
}

#[test]
fn ffi_encrypt_decrypt_message() {
    let payload_json = serde_json::json!({
        "conversation_id": "conv",
        "recipient_device_id": "device",
        "plaintext": "hi",
        "message_type": "text"
    })
    .to_string();

    let mut err = ExternError::default();
    let payload_c = CString::new(payload_json.clone()).unwrap();
    let payload_str = FfiStr::from_cstr(&payload_c);
    let encrypted_ptr = fc_encrypt_message(payload_str, &mut err);
    assert_success(&err);
    let encrypted_json = take_string(encrypted_ptr);

    let mut err = ExternError::default();
    let encrypted_c = CString::new(encrypted_json.clone()).unwrap();
    let decrypted_ptr = fc_decrypt_message(FfiStr::from_cstr(&encrypted_c), &mut err);
    assert_success(&err);
    let decrypted_json = take_string(decrypted_ptr);
    let decrypted: Value = serde_json::from_str(&decrypted_json).expect("json");
    assert_eq!(decrypted["plaintext"], "hi");
}

#[test]
fn ffi_rotate_group_sender_key() {
    let mut err = ExternError::default();
    let conv = CString::new("conv").unwrap();
    let init_ptr = fc_group_sender_key_init(FfiStr::from_cstr(&conv), &mut err);
    assert_success(&err);
    let init_json = take_string(init_ptr);

    let mut err = ExternError::default();
    let init_c = CString::new(init_json.clone()).unwrap();
    let rotate_ptr = fc_group_sender_key_rotate(FfiStr::from_cstr(&init_c), &mut err);
    assert_success(&err);
    let rotate_json = take_string(rotate_ptr);

    let initial: Value = serde_json::from_str(&init_json).expect("json");
    let rotated: Value = serde_json::from_str(&rotate_json).expect("json");
    assert_eq!(
        rotated["generation"].as_u64().unwrap(),
        initial["generation"].as_u64().unwrap() + 1
    );
    assert_ne!(rotated["key_material"], initial["key_material"]);
}
