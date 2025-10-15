use base64::{engine::general_purpose::STANDARD, Engine};
use rand::rngs::OsRng;
use rand::RngCore;
use serde::Serialize;

use crate::error::{CryptoError, CryptoResult};

#[derive(Debug, Serialize)]
pub struct PreKeyRecord {
    pub key_id: u32,
    pub public_key: String,
}

#[derive(Debug, Serialize)]
pub struct PreKeyBundle {
    pub identity: super::identity::IdentityBundle,
    pub prekeys: Vec<PreKeyRecord>,
}

pub fn generate_prekeys(count: u32) -> CryptoResult<Vec<PreKeyRecord>> {
    let count = count.min(1000);
    let mut output = Vec::with_capacity(count as usize);
    for _ in 0..count {
        let mut key = [0u8; 32];
        OsRng
            .try_fill_bytes(&mut key)
            .map_err(|_| CryptoError::Signal("prekey generation failed".into()))?;
        output.push(PreKeyRecord {
            key_id: OsRng.next_u32(),
            public_key: STANDARD.encode(key),
        });
    }
    Ok(output)
}

pub fn generate_bundle(count: u32) -> CryptoResult<PreKeyBundle> {
    Ok(PreKeyBundle {
        identity: super::identity::generate_identity_bundle()?,
        prekeys: generate_prekeys(count)?,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn generate_prekeys_caps_count() {
        let prekeys = generate_prekeys(1500).expect("prekeys");
        assert_eq!(prekeys.len(), 1000);
        assert!(prekeys.iter().all(|pk| pk.public_key.len() == 44));
    }

    #[test]
    fn generate_bundle_embeds_identity() {
        let bundle = generate_bundle(5).expect("bundle");
        assert_eq!(bundle.prekeys.len(), 5);
        assert!(!bundle.identity.device_id.is_empty());
    }
}
