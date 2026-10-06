/// Titles the manual workout already shows. No other phrase is an announcement.
enum SpokenAnnouncement { sessionPaused, rest, exercisePaused }

/// Maps one announcement to the caption already on screen.
///
/// The argument is the announcement itself. Callers cannot pass a free string.
String spokenCueText(SpokenAnnouncement announcement) {
  switch (announcement) {
    case SpokenAnnouncement.sessionPaused:
      return 'Session paused';
    case SpokenAnnouncement.rest:
      return 'Rest';
    case SpokenAnnouncement.exercisePaused:
      return 'Exercise paused';
  }
}

/// The announcement for the current manual session, if that screen has one.
SpokenAnnouncement? spokenAnnouncementFor({
  required bool reporting,
  required String state,
}) {
  if (reporting || state == 'pain_check') {
    return SpokenAnnouncement.exercisePaused;
  }
  switch (state) {
    case 'paused':
      return SpokenAnnouncement.sessionPaused;
    case 'resting':
      return SpokenAnnouncement.rest;
    default:
      return null;
  }
}
