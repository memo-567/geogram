/// Shared web navigation utilities for both Flutter and CLI modes
/// No Flutter dependencies - pure Dart only

/// Navigation item configuration
class NavItem {
  final String id;
  final String label;
  final String path;

  const NavItem({
    required this.id,
    required this.label,
    required this.path,
  });
}

/// Standard navigation items available across pages
class WebNavigation {
  /// Generate menu items as <li> elements for the navigation menu
  /// Format: "prefix > app1 | app2 | app3"
  ///
  /// Parameters:
  /// - [availableApps]: List of app IDs that should be shown
  /// - [activeApp]: The currently active app ID
  /// - [isStationPage]: If true, uses absolute paths (/chat/), otherwise relative (../chat/)
  /// - [prefix]: Text to show before the menu items (e.g., "station")
  ///
  /// Returns HTML string with <li> elements
  static String generateMenuItems({
    required List<String> availableApps,
    required String activeApp,
    bool isStationPage = false,
    String? prefix,
  }) {
    final buffer = StringBuffer();

    // Add prefix if provided
    if (prefix != null && prefix.isNotEmpty) {
      buffer.writeln('<li>$prefix &gt;</li>');
    }

    final items = <String>[];
    for (final appId in availableApps) {
      final item = _navItems[appId];
      if (item == null) continue;

      String href;
      if (isStationPage) {
        href = item.path;
      } else {
        // For device pages, use relative paths
        if (item.path == '/') {
          href = '../';
        } else {
          href = '../${item.path.substring(1)}';
        }
      }

      final isActive = appId == activeApp;
      if (isActive) {
        items.add('<li class="active"><a href="$href">${item.label}</a></li>');
      } else {
        items.add('<li><a href="$href">${item.label}</a></li>');
      }
    }

    // Join items with pipe separator
    buffer.write(items.join('<li class="separator">|</li>'));

    return buffer.toString();
  }

  /// Generate menu items for station pages
  static String generateStationMenuItems({
    required String activeApp,
    bool hasBlog = false,
    bool hasChat = true,
    bool hasEvents = false,
    bool hasPlaces = false,
    bool hasFiles = false,
    bool hasAlerts = false,
    bool hasDownload = false,
  }) {
    final apps = <String>['home'];
    if (hasBlog) apps.add('blog');
    if (hasChat) apps.add('chat');
    if (hasEvents) apps.add('events');
    if (hasPlaces) apps.add('places');
    if (hasFiles) apps.add('files');
    if (hasAlerts) apps.add('alerts');
    if (hasDownload) apps.add('download');

    return generateMenuItems(
      availableApps: apps,
      activeApp: activeApp,
      isStationPage: true,
      prefix: 'station',
    );
  }

  /// Generate menu items for device/collection pages
  static String generateDeviceMenuItems({
    required String activeApp,
    bool hasBlog = false,
    bool hasChat = true,
    bool hasEvents = false,
    bool hasPlaces = false,
    bool hasFiles = false,
    bool hasAlerts = false,
    bool hasDownload = false,
  }) {
    final apps = <String>['home'];
    if (hasBlog) apps.add('blog');
    if (hasChat) apps.add('chat');
    if (hasEvents) apps.add('events');
    if (hasPlaces) apps.add('places');
    if (hasFiles) apps.add('files');
    if (hasAlerts) apps.add('alerts');
    if (hasDownload) apps.add('download');

    return generateMenuItems(
      availableApps: apps,
      activeApp: activeApp,
      isStationPage: false,
    );
  }

  /// Standard navigation items
  static const Map<String, NavItem> _navItems = {
    'home': NavItem(id: 'home', label: 'home', path: '/'),
    'blog': NavItem(id: 'blog', label: 'blog', path: '/blog/'),
    'chat': NavItem(id: 'chat', label: 'chat', path: '/chat/'),
    'events': NavItem(id: 'events', label: 'events', path: '/events/'),
    'places': NavItem(id: 'places', label: 'places', path: '/places/'),
    'shared_folder': NavItem(id: 'shared_folder', label: 'shared_folder', path: '/shared_folder/'),
    'alerts': NavItem(id: 'alerts', label: 'alerts', path: '/alerts/'),
    'download': NavItem(id: 'download', label: 'download', path: '/download/'),
  };

  /// Get the CSS for header navigation
  /// This can be included inline or in theme files
  static String getHeaderNavCss() {
    return '''
/* Header Navigation - Combined breadcrumb style */
.header-nav {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  font-size: 1.1rem;
  padding: 10px 0;
}
.header-nav .nav-name {
  color: var(--accent);
  text-decoration: none;
  font-weight: bold;
}
.header-nav .nav-name:hover {
  text-decoration: underline;
}
.header-nav .nav-separator {
  color: var(--accent-alpha-70);
  margin: 0 2px;
}
.header-nav .nav-pipe {
  color: var(--accent-alpha-70);
}
.header-nav .nav-item {
  color: var(--color);
  text-decoration: none;
}
.header-nav .nav-item:hover {
  color: var(--accent);
}
.header-nav .nav-item.active {
  color: var(--accent-alpha-70);
}''';
  }
}
