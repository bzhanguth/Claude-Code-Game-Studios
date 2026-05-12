## SettingsData — SETTINGS domain of settings.save (NOT progress.save)
##
## Per save-persistence.md Rule 4 + Rule 18 (MVP stub). Extended by Settings &
## Accessibility (#18) when that GDD lands.
##
## Schema fields:
##   - audio_master_volume: float    [0.0, 1.0]
##   - haptics_enabled: bool         iOS Core Haptics / Android Vibrator gate
##   - accessibility_flags: Array[String]  reserved for future flags (high-contrast,
##                                          reduce-motion, etc.)
##
## Boot defaults: 1.0 / true / [] — audio on, haptics on, no accessibility flags.
##
## File separation rationale (Save Rule 4): Settings lives in user://settings.save
## NOT in user://progress.save so that "reset progress, keep accessibility prefs"
## flows need no engineering, and a corrupted progress.save cannot lose user
## preferences.
class_name SettingsData
extends Resource

@export_range(0.0, 1.0, 0.01) var audio_master_volume: float = 1.0
@export var haptics_enabled: bool = true
@export var accessibility_flags: Array[String] = []
