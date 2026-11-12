//
//  Spotify.js
//  FineTune (BeardedSpice Strategy)
//

BSStrategy = {
  version: 3,
  displayName: "Spotify Web",
  accepts: {
    method: "predicateOnTab",
    format: "%K LIKE[c] '*open.spotify.com*'",
    args: ["URL"]
  },
  isPlaying: function() {
    if (navigator.mediaSession && navigator.mediaSession.playbackState === 'playing') return true;
    var btn = document.querySelector('[data-testid="control-button-playpause"]');
    if (btn) {
      var label = (btn.getAttribute('aria-label') || '').toLowerCase();
      if (label.includes('pause') || label.includes('pausa')) return true;
    }
    var legacy = document.querySelector('.control-button--circled');
    return legacy ? legacy.classList.contains('spoticon-pause-16') : false;
  },
  toggle: function () {
    var btn = document.querySelector('[data-testid="control-button-playpause"], .control-button--circled');
    if (btn) { btn.click(); }
  },
  next: function () {
    var btn = document.querySelector('[data-testid="control-button-skip-forward"], .spoticon-skip-forward-16');
    if (btn) { btn.click(); }
  },
  favorite: function () {
    var btn = document.querySelector('[data-testid="add-button"], .spoticon-add-16');
    if (btn) { btn.click(); }
  },
  previous: function () {
    var btn = document.querySelector('[data-testid="control-button-skip-back"], .spoticon-skip-back-16');
    if (btn) { btn.click(); }
  },
  pause: function () {
    var btn = document.querySelector('[data-testid="control-button-playpause"]');
    if (btn) {
      var label = (btn.getAttribute('aria-label') || '').toLowerCase();
      if (label.includes('pause') || label.includes('pausa')) { btn.click(); }
    }
  },
  trackInfo: function () {
    var meta = (navigator.mediaSession && navigator.mediaSession.metadata) ? navigator.mediaSession.metadata : null;
    var trackEl = document.querySelector('[data-testid="context-item-info-title"], .track-info__name a');
    var artistEl = document.querySelector('[data-testid="context-item-info-subtitles"], .track-info__artists a');
    var imgEl = document.querySelector('[data-testid="cover-art-image"]');
    return {
      'image': (meta && meta.artwork && meta.artwork.length) ? meta.artwork[meta.artwork.length - 1].src : (imgEl ? imgEl.src : ''),
      'track': (meta && meta.title) ? meta.title : (trackEl ? trackEl.textContent.trim() : document.title),
      'artist': (meta && meta.artist) ? meta.artist : (artistEl ? artistEl.textContent.trim() : 'Spotify')
    };
  }
}
