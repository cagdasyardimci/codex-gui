use semver::Version;
use thiserror::Error;

const BASELINE: Version = Version::new(0, 153, 2);
const REMOTE_ACCESS_TARGET: Version = Version::new(0, 163, 0);

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CliQualification {
    Baseline,
    RemoteAccessTarget,
    Unverified,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CliCompatibility {
    version: Version,
    qualification: CliQualification,
}

#[derive(Debug, Error)]
pub enum CompatibilityError {
    #[error("Codex CLI version output does not report a semantic version")]
    UnknownVersion,
    #[error("Codex CLI {found} is below the supported baseline {minimum}")]
    BelowBaseline { found: Version, minimum: Version },
}

impl CliCompatibility {
    pub fn from_version_output(output: &str) -> Result<Self, CompatibilityError> {
        let version = output
            .split_whitespace()
            .last()
            .and_then(|token| Version::parse(token).ok())
            .ok_or(CompatibilityError::UnknownVersion)?;
        if version < BASELINE {
            return Err(CompatibilityError::BelowBaseline {
                found: version,
                minimum: BASELINE,
            });
        }

        let qualification = if version == BASELINE {
            CliQualification::Baseline
        } else if version == REMOTE_ACCESS_TARGET {
            CliQualification::RemoteAccessTarget
        } else {
            CliQualification::Unverified
        };
        Ok(Self {
            version,
            qualification,
        })
    }

    pub fn version(&self) -> &Version {
        &self.version
    }

    /// Identifies the checked CLI release profile. Provider and host eligibility are separate.
    pub fn qualification(&self) -> CliQualification {
        self.qualification
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn distinguishes_the_reference_releases_from_unverified_versions() {
        for (report, expected) in [
            ("codex-cli 0.153.2", CliQualification::Baseline),
            ("codex-cli 0.163.0", CliQualification::RemoteAccessTarget),
            ("codex-cli 0.163.1", CliQualification::Unverified),
            ("codex-cli 0.163.0+custom", CliQualification::Unverified),
        ] {
            assert_eq!(
                CliCompatibility::from_version_output(report)
                    .unwrap()
                    .qualification(),
                expected
            );
        }
    }

    #[test]
    fn rejects_versions_below_the_release_floor_and_unparseable_reports() {
        for report in ["codex-cli 0.153.1", "codex-cli 0.153.2-rc.1"] {
            assert!(matches!(
                CliCompatibility::from_version_output(report),
                Err(CompatibilityError::BelowBaseline { .. })
            ));
        }
        assert!(matches!(
            CliCompatibility::from_version_output("not a version"),
            Err(CompatibilityError::UnknownVersion)
        ));
    }
}
