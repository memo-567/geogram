/// Shared HTML templates for station server pages
/// Pure Dart - no Flutter dependencies
/// Used by both Flutter embedded and CLI station servers

import 'html_utils.dart';

/// Shared HTML templates for station server pages
class StationHtmlTemplates {
  /// Common CSS variables and base styles (Terminimal theme)
  static String getBaseStyles() {
    return '''
/* Terminimal theme */
:root {
  --accent: rgb(255,168,106);
  --accent-alpha-70: rgba(255,168,106,.7);
  --accent-alpha-20: rgba(255,168,106,.2);
  --background: #101010;
  --color: #f0f0f0;
  --border-color: rgba(255,240,224,.125);
  --shadow: 0 4px 6px rgba(0,0,0,.3);
}
@media (prefers-color-scheme: light) {
  :root {
    --accent: rgb(240,128,48);
    --accent-alpha-70: rgba(240,128,48,.7);
    --accent-alpha-20: rgba(240,128,48,.2);
    --background: white;
    --color: #201030;
    --border-color: rgba(0,0,16,.125);
    --shadow: 0 4px 6px rgba(0,0,0,.1);
  }
}
html { box-sizing: border-box; }
*, *:before, *:after { box-sizing: inherit; }
body {
  margin: 0; padding: 0;
  font-family: Hack, DejaVu Sans Mono, Monaco, Consolas, Ubuntu Mono, monospace;
  font-size: 1rem; line-height: 1.54;
  background-color: var(--background); color: var(--color);
  text-rendering: optimizeLegibility;
  -webkit-font-smoothing: antialiased;
}
a { color: inherit; }
h1, h2, h3 { font-weight: bold; line-height: 1.3; }
h1 { font-size: 1.4rem; }
h2 { font-size: 1.2rem; margin: 0 0 20px 0; }
h3 { font-size: 1rem; margin: 0 0 10px 0; color: var(--accent); }

.container {
  display: flex;
  flex-direction: column;
  padding: 40px;
  max-width: 864px;
  min-height: 100vh;
  margin: 0 auto;
}
@media (max-width: 683px) {
  .container { padding: 20px; }
}
.header {
  display: flex;
  flex-direction: column;
  position: relative;
  margin-bottom: 30px;
}
.header__inner {
  display: flex;
  align-items: center;
  justify-content: space-between;
}
.header__logo {
  display: flex;
  flex: 1;
}
.header__logo:after {
  content: "";
  background: repeating-linear-gradient(90deg, var(--accent), var(--accent) 2px, transparent 0, transparent 16px);
  display: block;
  width: 100%;
  right: 10px;
}
.logo {
  display: flex;
  align-items: center;
  text-decoration: none;
  background: var(--accent);
  color: #000;
  padding: 5px 10px;
}
.menu { margin: 20px 0; }
.menu__inner {
  display: flex;
  flex-wrap: wrap;
  list-style: none;
  margin: 0;
  padding: 0;
}
.menu__inner li {
  margin-right: 8px;
  margin-bottom: 10px;
  flex: 0 0 auto;
}
.menu__inner li.active a {
  color: var(--accent);
  font-weight: bold;
}
.menu__inner li.separator {
  color: var(--accent-alpha-70);
  margin-right: 8px;
}
.menu__inner a {
  color: inherit;
  text-decoration: none;
}
.menu__inner a:hover { color: var(--accent); }
.main { flex: 1; }

/* Footer */
.footer {
  padding: 30px 0;
  border-top: 1px solid var(--border-color);
  margin-top: auto;
  text-align: center;
  color: var(--accent-alpha-70);
  font-size: 0.9rem;
}
.footer a { color: var(--accent); text-decoration: none; }
.footer a:hover { text-decoration: underline; }
''';
  }

  /// CSS styles specific to download page
  static String getDownloadStyles() {
    return '''
/* Download Sections */
.download-section { margin-bottom: 40px; }
.section-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding-bottom: 15px;
  border-bottom: 1px solid var(--border-color);
  margin-bottom: 20px;
}
.section-header h2 { margin: 0; }
.download-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
  gap: 15px;
}
.download-card {
  display: flex;
  align-items: center;
  gap: 15px;
  background: var(--background);
  border: 1px solid var(--border-color);
  border-radius: 8px;
  padding: 15px;
  text-decoration: none;
  transition: border-color 0.2s ease, box-shadow 0.2s ease;
}
.download-card:hover {
  border-color: var(--accent);
  box-shadow: var(--shadow);
}
.download-icon {
  font-size: 1.5rem;
  flex-shrink: 0;
}
.download-name {
  font-weight: bold;
  flex-shrink: 0;
  margin-right: 10px;
}
.download-size {
  font-size: 0.85rem;
  color: var(--accent-alpha-70);
}
.download-desc {
  font-size: 0.85rem;
  color: var(--accent-alpha-70);
}

/* Model list */
.model-list { display: flex; flex-direction: column; gap: 10px; }
.model-item {
  display: flex;
  align-items: center;
  gap: 15px;
  padding: 12px 15px;
  background: var(--accent-alpha-20);
  border-radius: 6px;
  text-decoration: none;
  transition: background 0.2s ease;
}
.model-item:hover { background: var(--accent-alpha-70); }
.model-icon {
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 8px;
  background: var(--accent);
  border-radius: 6px;
  min-width: 40px;
  min-height: 40px;
}
.model-icon svg {
  width: 24px;
  height: 24px;
  fill: none;
  stroke: var(--background);
  stroke-width: 2;
  stroke-linecap: round;
  stroke-linejoin: round;
}
.model-name { font-weight: bold; flex: 1; }
.model-size { color: var(--accent-alpha-70); font-size: 0.9rem; min-width: 80px; text-align: right; }
.model-desc { color: var(--accent-alpha-70); font-size: 0.85rem; flex: 2; }

@media (max-width: 600px) {
  .download-grid { grid-template-columns: 1fr 1fr; }
  .model-item { flex-wrap: wrap; }
  .model-desc { width: 100%; margin-top: 5px; }
  .model-size { min-width: auto; }
}
''';
  }

  /// Build download page HTML
  /// [availableAssets] maps asset type (androidApk, linuxDesktop, etc.) to download URL
  /// [availableWhisperModels] list of whisper model definitions that are available
  /// [releaseVersion] the current release version
  /// [releaseNotes] the changelog/release notes from GitHub
  static String buildDownloadPage({
    required String stationName,
    required String menuItems,
    Map<String, String>? availableAssets,
    List<Map<String, dynamic>>? availableWhisperModels,
    String? releaseVersion,
    String? releaseNotes,
  }) {
    // Build platform download cards based on available assets
    final platformCards = _buildPlatformCards(availableAssets);

    // Build whisper models section
    final whisperModelsHtml = _buildWhisperModelsHtml(availableWhisperModels);

    // Build changelog section
    final changelogHtml = releaseNotes != null && releaseNotes.isNotEmpty
        ? '''
      <section class="download-section">
        <div class="section-header">
          <h2>Changelog</h2>
        </div>
        <div class="changelog">
          <pre>${escapeHtml(releaseNotes)}</pre>
        </div>
      </section>
      '''
        : '';

    // Version suffix for header
    final versionSuffix = releaseVersion != null ? ' v$releaseVersion' : '';

    return '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Downloads - ${escapeHtml(stationName)}</title>
  <style>
${getBaseStyles()}
${getDownloadStyles()}
.changelog {
  background: var(--accent-alpha-20);
  border-radius: 6px;
  padding: 15px;
  overflow-x: auto;
}
.changelog pre {
  margin: 0;
  white-space: pre-wrap;
  word-wrap: break-word;
  font-size: 0.9rem;
  line-height: 1.5;
}
  </style>
</head>
<body>
  <div class="container">
    <header class="header">
      <div class="header__inner">
        <div class="header__logo">
          <a href="/" style="text-decoration: none;">
            <div class="logo">${escapeHtml(stationName)}</div>
          </a>
        </div>
      </div>
      <nav class="menu">
        <ul class="menu__inner">
          $menuItems
        </ul>
      </nav>
    </header>

    <main class="main">
      <!-- Application Downloads -->
      <section class="download-section">
        <div class="section-header">
          <h2>Geogram$versionSuffix</h2>
        </div>
        $platformCards
      </section>

      $changelogHtml

      <!-- Speech Recognition Models -->
      $whisperModelsHtml

      <!-- Vision AI Models -->
      <section class="download-section">
        <div class="section-header">
          <h2>Vision AI Models</h2>
        </div>
        <div class="model-list">
          <a href="/bot/models/vision/mobilenet-v3-small.tflite" class="model-item">
            <span class="model-icon"><svg viewBox="0 0 24 24"><path d="M12 3v12m0 0l-4-4m4 4l4-4M5 17v2a2 2 0 002 2h10a2 2 0 002-2v-2"/></svg></span>
            <span class="model-name">MobileNet V3 Small</span>
            <span class="model-size">~10 MB</span>
            <span class="model-desc">Fast image classification</span>
          </a>
          <a href="/bot/models/vision/mobilenet-v4-medium.tflite" class="model-item">
            <span class="model-icon"><svg viewBox="0 0 24 24"><path d="M12 3v12m0 0l-4-4m4 4l4-4M5 17v2a2 2 0 002 2h10a2 2 0 002-2v-2"/></svg></span>
            <span class="model-name">MobileNet V4 Medium</span>
            <span class="model-size">~19 MB</span>
            <span class="model-desc">Better accuracy classification</span>
          </a>
          <a href="/bot/models/vision/efficientdet-lite0.tflite" class="model-item">
            <span class="model-icon"><svg viewBox="0 0 24 24"><path d="M12 3v12m0 0l-4-4m4 4l4-4M5 17v2a2 2 0 002 2h10a2 2 0 002-2v-2"/></svg></span>
            <span class="model-name">EfficientDet Lite</span>
            <span class="model-size">~20 MB</span>
            <span class="model-desc">Object detection</span>
          </a>
          <a href="/bot/models/vision/llava-7b-q4.gguf" class="model-item">
            <span class="model-icon"><svg viewBox="0 0 24 24"><path d="M12 3v12m0 0l-4-4m4 4l4-4M5 17v2a2 2 0 002 2h10a2 2 0 002-2v-2"/></svg></span>
            <span class="model-name">LLaVA 7B (Q4)</span>
            <span class="model-size">~4.1 GB</span>
            <span class="model-desc">Full visual Q&A</span>
          </a>
          <a href="/bot/models/vision/llava-7b-q5.gguf" class="model-item">
            <span class="model-icon"><svg viewBox="0 0 24 24"><path d="M12 3v12m0 0l-4-4m4 4l4-4M5 17v2a2 2 0 002 2h10a2 2 0 002-2v-2"/></svg></span>
            <span class="model-name">LLaVA 7B (Q5)</span>
            <span class="model-size">~4.8 GB</span>
            <span class="model-desc">Better quality visual Q&A</span>
          </a>
        </div>
      </section>
    </main>

    <footer class="footer">
      <span>Powered by Geogram</span>
    </footer>
  </div>
</body>
</html>
''';
  }

  /// Build whisper models HTML section based on available models
  static String _buildWhisperModelsHtml(List<Map<String, dynamic>>? models) {
    if (models == null || models.isEmpty) {
      return '''
      <section class="download-section">
        <div class="section-header">
          <h2>Speech Recognition Models (Whisper)</h2>
        </div>
        <p style="color: var(--accent-alpha-70);">
          No whisper models available yet. The station will sync models automatically.
        </p>
      </section>
      ''';
    }

    final modelItems = models.map((m) {
      final id = m['id'] as String;
      final name = m['name'] as String;
      final size = m['size'] as int;
      final description = m['description'] as String;
      final sizeMb = (size / (1024 * 1024)).round();
      final sizeStr = sizeMb >= 1000 ? '~${(sizeMb / 1024).toStringAsFixed(1)} GB' : '~$sizeMb MB';

      return '''
          <a href="/bot/models/whisper/$id" class="model-item">
            <span class="model-icon"><svg viewBox="0 0 24 24"><path d="M12 3v12m0 0l-4-4m4 4l4-4M5 17v2a2 2 0 002 2h10a2 2 0 002-2v-2"/></svg></span>
            <span class="model-name">$name</span>
            <span class="model-size">$sizeStr</span>
            <span class="model-desc">$description</span>
          </a>
      ''';
    }).join('\n');

    return '''
      <section class="download-section">
        <div class="section-header">
          <h2>Speech Recognition Models (Whisper)</h2>
        </div>
        <div class="model-list">
          $modelItems
        </div>
      </section>
    ''';
  }

  /// Build platform download cards based on available assets
  static String _buildPlatformCards(Map<String, String>? availableAssets) {
    if (availableAssets == null || availableAssets.isEmpty) {
      return '''
        <p style="color: var(--accent-alpha-70);">
          No application binaries available yet. The station will sync releases automatically.
        </p>
      ''';
    }

    final cards = <String>[];

    // Android APK (kebab-case key from release.json)
    if (availableAssets.containsKey('android-apk')) {
      cards.add(_buildPlatformCard(
        url: availableAssets['android-apk']!,
        icon: '&#129302;', // Robot face for Android
        name: 'Android',
        desc: 'APK for Android devices',
      ));
    }

    // Linux Desktop (kebab-case key from release.json)
    if (availableAssets.containsKey('linux-desktop')) {
      cards.add(_buildPlatformCard(
        url: availableAssets['linux-desktop']!,
        icon: '&#128039;', // Penguin for Linux
        name: 'Linux',
        desc: 'tar.gz for Linux x64',
      ));
    }

    // Windows Desktop (kebab-case key from release.json)
    if (availableAssets.containsKey('windows-desktop')) {
      cards.add(_buildPlatformCard(
        url: availableAssets['windows-desktop']!,
        icon: '&#128187;', // Computer for Windows
        name: 'Windows',
        desc: 'ZIP for Windows x64',
      ));
    }

    // macOS Desktop (kebab-case key from release.json)
    if (availableAssets.containsKey('macos-desktop')) {
      cards.add(_buildPlatformCard(
        url: availableAssets['macos-desktop']!,
        icon: '&#127822;', // Apple for macOS
        name: 'macOS',
        desc: 'ZIP for macOS x64',
      ));
    }

    if (cards.isEmpty) {
      return '''
        <p style="color: var(--accent-alpha-70);">
          No application binaries available yet. The station will sync releases automatically.
        </p>
      ''';
    }

    return '<div class="download-grid">${cards.join('\n')}</div>';
  }

  /// Build a single platform download card
  static String _buildPlatformCard({
    required String url,
    required String icon,
    required String name,
    required String desc,
  }) {
    return '''
          <a href="$url" class="download-card">
            <div class="download-icon">$icon</div>
            <div class="download-name">$name</div>
            <div class="download-desc">$desc</div>
          </a>
    ''';
  }

  /// Build simple navigation HTML for download page
  /// Format: home | download (active)
  static String buildDownloadNavigation({bool isActive = true}) {
    if (isActive) {
      return '''<a href="/">home</a>
        <span class="separator">|</span>
        <span class="active">download</span>''';
    } else {
      return '''<a href="/">home</a>
        <span class="separator">|</span>
        <a href="/download/">download</a>''';
    }
  }

  /// JavaScript for dynamic updates (shared between both servers)
  static String getDynamicUpdateScript() {
    return '''
    // Dynamic updates every 10 seconds
    setInterval(async function() {
      try {
        const response = await fetch('/api/clients');
        const data = await response.json();
        updateDeviceCards(data.clients || []);
      } catch (e) {
        console.error('Failed to refresh devices:', e);
      }
    }, 10000);

    function formatTimeAgo(isoString) {
      const then = new Date(isoString);
      const now = new Date();
      const diff = Math.floor((now - then) / 1000);

      if (diff >= 2592000) { // 30 days
        const months = Math.floor(diff / 2592000);
        return months + (months === 1 ? ' month' : ' months') + ' ago';
      } else if (diff >= 604800) { // 7 days
        const weeks = Math.floor(diff / 604800);
        return weeks + (weeks === 1 ? ' week' : ' weeks') + ' ago';
      } else if (diff >= 86400) {
        const days = Math.floor(diff / 86400);
        return days + (days === 1 ? ' day' : ' days') + ' ago';
      } else if (diff >= 3600) {
        const hours = Math.floor(diff / 3600);
        return hours + (hours === 1 ? ' hour' : ' hours') + ' ago';
      } else if (diff >= 60) {
        const minutes = Math.floor(diff / 60);
        return minutes + (minutes === 1 ? ' minute' : ' minutes') + ' ago';
      } else {
        return 'just now';
      }
    }

    function escapeHtml(text) {
      const div = document.createElement('div');
      div.textContent = text;
      return div.innerHTML;
    }

    function updateDeviceCards(clients) {
      const grid = document.querySelector('.devices-grid');
      const emptyState = document.querySelector('.no-devices');

      if (!grid || !emptyState) return;

      if (clients.length === 0) {
        grid.style.display = 'none';
        emptyState.style.display = 'block';
        return;
      }

      grid.style.display = 'grid';
      emptyState.style.display = 'none';

      // Rebuild device cards
      grid.innerHTML = clients.map(c => {
        const callsign = c.callsign || 'Unknown';
        const nickname = c.nickname || callsign;
        const connType = c.connection_type || 'internet';
        const connLabel = connType.charAt(0).toUpperCase() + connType.slice(1);
        const location = (c.latitude && c.longitude)
          ? ' · ' + c.latitude.toFixed(2) + ', ' + c.longitude.toFixed(2)
          : '';
        return '<a href="/' + callsign + '/" class="device-card">' +
          '<div class="device-header">' +
            '<span class="device-callsign">' + escapeHtml(callsign) + '</span>' +
            '<span class="connection-badge ' + connType + '">' + connLabel + '</span>' +
          '</div>' +
          '<div class="device-nickname">' + escapeHtml(nickname) + '</div>' +
          '<div class="device-meta">' +
            'Connected since ' + formatTimeAgo(c.connected_at) + location +
          '</div>' +
        '</a>';
      }).join('');
    }
''';
  }
}
