use base64::{engine::general_purpose::STANDARD, Engine};
use rand::rngs::OsRng;
use rand::RngCore;
use serde::Serialize;
use uuid::Uuid;

use crate::error::{CryptoError, CryptoResult};

#[derive(Debug, Serialize)]
pub struct IdentityBundle {
    pub device_id: String,
    pub registration_id: u32,
    pub identity_key: String,
    pub signed_prekey: SignedPreKeyStub,
}

#[derive(Debug, Serialize)]
pub struct SignedPreKeyStub {
    pub key_id: u32,
    pub public_key: String,
    pub signature: String,
}

/// Generates a placeholder identity bundle. Replace with libsignal-client integration.
pub fn generate_identity_bundle() -> CryptoResult<IdentityBundle> {
    let mut identity_key = [0u8; 32];
    let mut signed_prekey = [0u8; 32];
    let mut signature = [0u8; 64];

    OsRng
        .try_fill_bytes(&mut identity_key)
        .map_err(|_| CryptoError::Signal("identity key generation failed".into()))?;
    OsRng
        .try_fill_bytes(&mut signed_prekey)
        .map_err(|_| CryptoError::Signal("signed prekey generation failed".into()))?;
    OsRng
        .try_fill_bytes(&mut signature)
        .map_err(|_| CryptoError::Signal("signature generation failed".into()))?;

    Ok(IdentityBundle {
        device_id: Uuid::new_v4().to_string(),
        registration_id: OsRng.next_u32(),
        identity_key: STANDARD.encode(identity_key),
        signed_prekey: SignedPreKeyStub {
            key_id: OsRng.next_u32(),
            public_key: STANDARD.encode(signed_prekey),
            signature: STANDARD.encode(signature),
        },
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn identity_bundle_has_expected_lengths() {
        let bundle = generate_identity_bundle().expect("bundle");
        assert_eq!(bundle.identity_key.len(), 44);
        assert_eq!(bundle.signed_prekey.public_key.len(), 44);
        assert_eq!(bundle.signed_prekey.signature.len(), 88);
        assert!(!bundle.device_id.is_empty());
    }
}
