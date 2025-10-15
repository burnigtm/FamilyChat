use base64::{engine::general_purpose::STANDARD, Engine};
use rand::rngs::OsRng;
use rand::RngCore;
use serde::{Deserialize, Serialize};

use crate::error::{CryptoError, CryptoResult};

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct GroupSenderKey {
    pub conversation_id: String,
    pub generation: u32,
    pub key_material: String,
}

pub fn initialize_sender_key(conversation_id: impl Into<String>) -> CryptoResult<GroupSenderKey> {
    Ok(GroupSenderKey {
        conversation_id: conversation_id.into(),
        generation: 1,
        key_material: random_key_material()?,
    })
}

pub fn rotate_sender_key(existing: &GroupSenderKey) -> CryptoResult<GroupSenderKey> {
    Ok(GroupSenderKey {
        conversation_id: existing.conversation_id.clone(),
        generation: existing.generation + 1,
        key_material: random_key_material()?,
    })
}

fn random_key_material() -> CryptoResult<String> {
    let mut key = [0u8; 32];
    OsRng
        .try_fill_bytes(&mut key)
        .map_err(|_| CryptoError::Signal("group sender key generation failed".into()))?;
    Ok(STANDARD.encode(key))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rotate_sender_key_increments_generation() {
        let initial = initialize_sender_key("conv").expect("init");
        let rotated = rotate_sender_key(&initial).expect("rotate");
        assert_eq!(rotated.generation, initial.generation + 1);
        assert_ne!(rotated.key_material, initial.key_material);
    }
}
