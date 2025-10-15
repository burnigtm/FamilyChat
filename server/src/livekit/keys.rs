use base64::{engine::general_purpose::STANDARD, Engine};
use hkdf::Hkdf;
use sha2::Sha256;

const HKDF_SALT: &[u8] = b"familychat.livekit.e2ee";

pub fn derive_room_key(conversation_secret: &[u8], room_name: &str) -> [u8; 32] {
    let hk = Hkdf::<Sha256>::new(Some(HKDF_SALT), conversation_secret);
    let mut okm = [0u8; 32];
    hk.expand(room_name.as_bytes(), &mut okm)
        .expect("hkdf expand failure");
    okm
}

pub fn derive_room_key_base64(conversation_secret: &[u8], room_name: &str) -> String {
    STANDARD.encode(derive_room_key(conversation_secret, room_name))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn base64_key_is_deterministic() {
        let secret = b"conversation-secret";
        let room = "room-123";
        let key_a = derive_room_key_base64(secret, room);
        let key_b = derive_room_key_base64(secret, room);
        assert_eq!(key_a, key_b);
        assert_eq!(key_a.len(), 44); // 32 bytes -> 44 base64 chars
    }
}
