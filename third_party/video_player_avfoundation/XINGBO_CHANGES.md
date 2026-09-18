# Local iOS PiP extension

Based on the unmodified pub.dev video_player_avfoundation 2.12.0 package.
Original BSD license is retained in LICENSE.

VideoPlayerPlugin.swift registers XingboSharedPip.swift and detaches its layer
when the owning player or Flutter engine is disposed. The additional channel
uses the existing AVPlayer by player ID. No second AVPlayerItem is created,
and entering/restoring PiP does not seek, pause, or reload the source.
Closing PiP pauses the existing player; restoring keeps its playback state.
Android and macOS playback code is unchanged.

This extension requires compilation and playback verification on macOS/iOS.
