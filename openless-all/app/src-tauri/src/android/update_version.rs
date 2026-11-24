//! SemVer precedence shared by the Android updater and the standalone host tests.

pub fn version_is_newer(remote: &str, current: &str) -> bool {
    let (Ok(remote), Ok(current)) = (
        semver::Version::parse(remote),
        semver::Version::parse(current),
    ) else {
        return false;
    };
    remote.cmp_precedence(&current).is_gt()
}

#[cfg(test)]
mod fork_version_precedence_tests {
    use super::version_is_newer;

    #[test]
    fn build_metadata_does_not_offer_a_reinstall_or_downgrade() {
        assert!(!version_is_newer("2.1.0+build.2", "2.1.0+build.1"));
        assert!(!version_is_newer("2.1.0+build.1", "2.1.0+build.2"));
        assert!(version_is_newer("2.1.1", "2.1.0+build.2"));
        assert!(version_is_newer("2.1.0", "2.1.0-Beta.2"));
        assert!(!version_is_newer("2.0.2+build.20261115", "2.1.0"));
    }
}
