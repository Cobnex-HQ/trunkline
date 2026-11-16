use libp2p::identity;
use serde::{Deserialize, Serialize};
use std::path::Path;
#[derive(Serialize, Deserialize)]
pub struct DeviceConfig {
    pub key: Vec<u8>,
    pub expected: String,
}
impl DeviceConfig {
    pub fn load(path: &Path) -> anyhow::Result<Self> {
        Ok(serde_json::from_slice(&std::fs::read(path)?)?)
    }
    pub fn identity(&self) -> anyhow::Result<identity::Keypair> {
        Ok(identity::Keypair::from_protobuf_encoding(&self.key)?)
    }
}
pub fn pair(directory: &Path) -> anyhow::Result<()> {
    use std::{
        fs::{DirBuilder, OpenOptions},
        io::Write,
        os::unix::fs::{DirBuilderExt, OpenOptionsExt},
    };
    // create(), not create_dir_all(): an existing directory must never be reused.
    DirBuilder::new().mode(0o700).create(directory)?;
    let mac = identity::Keypair::generate_ed25519();
    let phone = identity::Keypair::generate_ed25519();
    for (name, key, expected) in [("mac.json", &mac, &phone), ("phone.json", &phone, &mac)] {
        let config = DeviceConfig {
            key: key.to_protobuf_encoding()?,
            expected: expected.public().to_peer_id().to_string(),
        };
        let mut file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(directory.join(name))?;
        file.write_all(&serde_json::to_vec(&config)?)?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt;
    #[test]
    fn identities_are_private_mutually_pinned_and_never_overwritten() {
        let directory =
            std::env::temp_dir().join(format!("trunkline-pair-{}", libp2p::PeerId::random()));
        pair(&directory).unwrap();
        let mac = DeviceConfig::load(&directory.join("mac.json")).unwrap();
        let phone = DeviceConfig::load(&directory.join("phone.json")).unwrap();
        assert_eq!(
            mac.expected,
            phone.identity().unwrap().public().to_peer_id().to_string()
        );
        assert_eq!(
            phone.expected,
            mac.identity().unwrap().public().to_peer_id().to_string()
        );
        assert_eq!(
            std::fs::metadata(&directory).unwrap().permissions().mode() & 0o777,
            0o700
        );
        assert_eq!(
            std::fs::metadata(directory.join("mac.json"))
                .unwrap()
                .permissions()
                .mode()
                & 0o777,
            0o600
        );
        assert!(pair(&directory).is_err());
        assert_eq!(
            DeviceConfig::load(&directory.join("mac.json")).unwrap().key,
            mac.key
        );
        std::fs::remove_dir_all(directory).unwrap();
    }
}
