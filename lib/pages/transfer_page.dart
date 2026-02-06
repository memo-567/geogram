import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path/path.dart' as p;

import '../pages/document_viewer_editor_page.dart';
import '../pages/photo_viewer_page.dart';
import '../services/file_launcher_service.dart';
import '../transfer/models/callsign_transfer_group.dart';
import '../transfer/models/transfer_metrics.dart';
import '../transfer/models/transfer_models.dart';
import '../transfer/models/transfer_offer.dart';
import '../transfer/services/transfer_metrics_service.dart';
import '../transfer/services/transfer_service.dart';
import '../transfer/services/p2p_transfer_service.dart';
import '../util/event_bus.dart';
import '../util/file_icon_helper.dart';
import '../widgets/transfer/transfer_activity_chart.dart';
import '../widgets/transfer/transfer_callsign_group_tile.dart';
import '../widgets/transfer/transfer_metrics_card.dart';
import '../widgets/transfer/incoming_transfer_dialog.dart';
import 'transfer_receive_page.dart';
import 'transfer_send_page.dart';

/// Main Transfer Center page
///
/// Features:
/// - Tab-based view: Active | Queued | Completed | Failed | Stats
/// - Real-time progress updates
/// - Swipe actions (pause, cancel, retry)
/// - Settings access
/// - Metrics summary card
class TransferPage extends StatefulWidget {
  const TransferPage({super.key});

  @override
  State<TransferPage> createState() => _TransferPageState();
}

class _TransferPageState extends State<TransferPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TransferService _service = TransferService();
  final TransferMetricsService _metricsService = TransferMetricsService();
  final EventBus _eventBus = EventBus();

  TransferMetrics _metrics = const TransferMetrics();
  List<Transfer> _activeTransfers = [];
  List<Transfer> _queuedTransfers = [];
  List<Transfer> _completedTransfers = [];
  List<Transfer> _failedTransfers = [];
  List<TransferHistoryPoint> _historyPoints = [];

  bool _isLoading = true;
  String? _error;
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};

  StreamSubscription? _metricsSubscription;
  EventSubscription<TransferProgressEvent>? _progressSubscription;
  EventSubscription<TransferCompletedEvent>? _completedSubscription;
  EventSubscription<TransferFailedEvent>? _failedSubscription;

  // P2P transfer state
  final P2PTransferService _p2pService = P2PTransferService();
  List<TransferOffer> _outgoingOffers = [];
  List<TransferOffer> _incomingOffers = [];
  EventSubscription<TransferOfferReceivedEvent>? _offerReceivedSubscription;
  EventSubscription<TransferOfferStatusChangedEvent>? _offerStatusSubscription;
  EventSubscription<P2PUploadProgressEvent>? _p2pProgressSubscription;
  EventSubscription<P2PDownloadProgressEvent>? _p2pDownloadProgressSubscription;
  EventSubscription<P2PTransferCompleteEvent>? _p2pCompleteSubscription;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _initService();
  }

  Future<void> _initService() async {
    try {
      if (!_service.isInitialized) {
        await _service.initialize();
      }
      await _metricsService.initialize();

      // Subscribe to updates
      _metricsSubscription = _service.metricsStream.listen((metrics) {
        if (mounted) {
          setState(() => _metrics = metrics);
        }
      });

      _progressSubscription = _eventBus.on<TransferProgressEvent>((event) {
        _refreshData();
      });

      _completedSubscription = _eventBus.on<TransferCompletedEvent>((event) {
        _refreshData();
      });

      _failedSubscription = _eventBus.on<TransferFailedEvent>((event) {
        _refreshData();
      });

      // P2P offer subscriptions
      _offerReceivedSubscription = _eventBus.on<TransferOfferReceivedEvent>((event) {
        _handleIncomingOffer(event);
      });

      _offerStatusSubscription = _eventBus.on<TransferOfferStatusChangedEvent>((event) {
        _refreshP2POffers();
      });

      _p2pProgressSubscription = _eventBus.on<P2PUploadProgressEvent>((event) {
        _refreshP2POffers();
      });

      _p2pDownloadProgressSubscription = _eventBus.on<P2PDownloadProgressEvent>((event) {
        _refreshP2POffers();
      });

      _p2pCompleteSubscription = _eventBus.on<P2PTransferCompleteEvent>((event) {
        _handleP2PTransferComplete(event);
      });

      await _refreshData();
      _refreshP2POffers();

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _refreshData() async {
    try {
      final metrics = _service.getMetrics();
      final active = _service.getActiveTransfers();
      final queued = _service.getQueuedTransfers();
      final completed = _service.getCompletedTransfers();
      final failed = _service.getFailedTransfers();
      final history = _metricsService.getHistory(
        period: const Duration(days: 1),
        resolution: const Duration(hours: 1),
      );

      // Merge P2P stats into metrics
      final mergedMetrics = _mergeP2PMetrics(metrics);

      if (mounted) {
        setState(() {
          _metrics = mergedMetrics;
          _activeTransfers = active;
          _queuedTransfers = queued;
          _completedTransfers = completed;
          _failedTransfers = failed;
          _historyPoints = history;
          _pruneSelection();
        });
      }
    } catch (e) {
      // Silently fail refresh
    }
  }

  /// Merge P2P transfer stats into the regular transfer metrics
  ///
  /// Only merges active/pending transfer counts for real-time UI.
  /// Completed stats now come from persisted storage via TransferMetricsService.
  TransferMetrics _mergeP2PMetrics(TransferMetrics base) {
    final outgoing = _p2pService.outgoingOffers;
    final incoming = _p2pService.incomingOffers;

    // Count active P2P transfers (still needed for real-time UI)
    final activeP2P = [
      ...outgoing.where((o) =>
          o.status == TransferOfferStatus.accepted ||
          o.status == TransferOfferStatus.transferring),
      ...incoming.where((o) =>
          o.status == TransferOfferStatus.accepted ||
          o.status == TransferOfferStatus.transferring),
    ].length;

    // Count pending outgoing offers as "queued"
    final pendingP2P = outgoing
        .where((o) => o.status == TransferOfferStatus.pending)
        .length;

    // Only merge active/pending counts - completed stats come from storage now
    return base.copyWith(
      activeTransfers: base.activeTransfers + activeP2P,
      queuedTransfers: base.queuedTransfers + pendingP2P,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _metricsSubscription?.cancel();
    _progressSubscription?.cancel();
    _completedSubscription?.cancel();
    _failedSubscription?.cancel();
    _offerReceivedSubscription?.cancel();
    _offerStatusSubscription?.cancel();
    _p2pProgressSubscription?.cancel();
    _p2pDownloadProgressSubscription?.cancel();
    _p2pCompleteSubscription?.cancel();
    super.dispose();
  }

  /// Refresh P2P offers
  void _refreshP2POffers() {
    if (mounted) {
      setState(() {
        _outgoingOffers = _p2pService.outgoingOffers;
        _incomingOffers = _p2pService.incomingOffers;
      });
    }
  }

  /// Handle incoming transfer offer - show dialog
  void _handleIncomingOffer(TransferOfferReceivedEvent event) async {
    _refreshP2POffers();

    final offer = _p2pService.getOffer(event.offerId);
    if (offer == null) return;

    // Show incoming offer dialog (mark as shown from TransferPage to avoid duplicate navigation)
    await IncomingTransferDialog.show(context, offer, shownFromTransferPage: true);

    // Dialog handles accept/reject, just refresh
    _refreshP2POffers();
  }

  /// Handle P2P transfer completion - show dialog with metrics
  void _handleP2PTransferComplete(P2PTransferCompleteEvent event) {
    _refreshP2POffers();

    if (!mounted) return;

    final offer = _p2pService.getOffer(event.offerId);
    final isIncoming = _incomingOffers.any((o) => o.offerId == event.offerId);
    final otherCallsign = offer != null
        ? (isIncoming ? offer.senderCallsign : offer.receiverCallsign ?? 'Unknown')
        : 'Unknown';

    // Show completion dialog
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              event.success ? Icons.check_circle : Icons.error,
              color: event.success ? Colors.green : Colors.red,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                event.success ? 'Transfer Complete' : 'Transfer Failed',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${isIncoming ? "From" : "To"}: $otherCallsign'),
            const SizedBox(height: 8),
            Text('Files: ${event.filesReceived}'),
            Text('Size: ${_formatBytes(event.bytesReceived)}'),
            if (offer?.transferDuration != null)
              Text('Duration: ${_formatDuration(offer!.transferDuration)}'),
            if (event.error != null) ...[
              const SizedBox(height: 8),
              Text(
                'Error: ${event.error}',
                style: TextStyle(color: Colors.red),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );

    // Switch to Previous tab
    _tabController.animateTo(1);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Transfers')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Transfers')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'Error initializing transfers',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(_error!, style: theme.textTheme.bodySmall),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _isLoading = true;
                    _error = null;
                  });
                  _initService();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transfers'),
        actions: [
          if (_selectionMode)
            IconButton(
              icon: const Icon(Icons.close_fullscreen),
              tooltip: 'Exit selection',
              onPressed: () {
                setState(() {
                  _selectionMode = false;
                  _selectedIds.clear();
                });
              },
            )
          else
            IconButton(
              icon: const Icon(Icons.checklist),
              tooltip: 'Select transfers',
              onPressed: () {
                setState(() {
                  _selectionMode = true;
                });
              },
            ),
          if (_selectionMode && _selectedIds.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.cancel_schedule_send),
              tooltip: 'Cancel selected',
              onPressed: _confirmCancelSelected,
            ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: _showSettings,
            tooltip: 'Settings',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.sync), text: 'In Progress'),
            Tab(icon: Icon(Icons.history), text: 'Previous'),
            Tab(icon: Icon(Icons.analytics), text: 'Stats'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildInProgressTab(),
          _buildPreviousTab(),
          _buildStatsTab(),
        ],
      ),
      floatingActionButton: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Send button
          FloatingActionButton(
            heroTag: 'transfer_send',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TransferSendPage()),
            ),
            tooltip: 'Send',
            child: SvgPicture.asset(
              'assets/icon_file_send.svg',
              width: 28,
              height: 28,
            ),
          ),
          const SizedBox(width: 12),
          // Receive button
          FloatingActionButton(
            heroTag: 'transfer_receive',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TransferReceivePage()),
            ),
            tooltip: 'Receive',
            child: SvgPicture.asset(
              'assets/icon_file_receive.svg',
              width: 28,
              height: 28,
            ),
          ),
        ],
      ),
    );
  }

  void _toggleSelection(String transferId, bool selected) {
    setState(() {
      if (selected) {
        _selectedIds.add(transferId);
      } else {
        _selectedIds.remove(transferId);
      }
    });
  }

  void _pruneSelection() {
    final validIds = {
      ..._activeTransfers.map((t) => t.id),
      ..._queuedTransfers.map((t) => t.id),
    };
    _selectedIds.removeWhere((id) => !validIds.contains(id));
  }

  Future<void> _confirmCancelSelected() async {
    if (_selectedIds.isEmpty) return;
    final count = _selectedIds.length;
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Cancel selected transfers'),
            content: Text('Cancel $count selected transfer(s)?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Keep'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Cancel Transfers'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;
    for (final id in List<String>.from(_selectedIds)) {
      await _service.cancel(id);
    }
    await _refreshData();
    if (mounted) {
      setState(() {
        _selectedIds.clear();
        _selectionMode = false;
      });
    }
  }

  Widget _buildInProgressTab() {
    final List<Transfer> combined = [
      ..._activeTransfers,
      ..._queuedTransfers,
    ];

    // Get active P2P offers (pending or transferring)
    final activeOutgoing = _outgoingOffers.where((o) =>
      o.status == TransferOfferStatus.pending ||
      o.status == TransferOfferStatus.accepted ||
      o.status == TransferOfferStatus.transferring
    ).toList();

    final activeIncoming = _incomingOffers.where((o) =>
      o.status == TransferOfferStatus.accepted ||
      o.status == TransferOfferStatus.transferring
    ).toList();

    if (combined.isEmpty && activeOutgoing.isEmpty && activeIncoming.isEmpty) {
      return _buildEmptyState(
        'No transfers in progress',
        'Active and queued transfers will appear here',
        Icons.sync,
      );
    }

    final groups = groupTransfersByCallsign(combined);

    return RefreshIndicator(
      onRefresh: () async {
        await _refreshData();
        _refreshP2POffers();
      },
      child: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 80),
        children: [
          // P2P Outgoing Offers Section
          if (activeOutgoing.isNotEmpty) ...[
            _buildSectionHeader('Pending Offers (Sent)'),
            ...activeOutgoing.map((offer) => _buildOfferTile(offer, isOutgoing: true)),
            const SizedBox(height: 8),
          ],

          // P2P Incoming Offers Section (active downloads)
          if (activeIncoming.isNotEmpty) ...[
            _buildSectionHeader('Receiving'),
            ...activeIncoming.map((offer) => _buildOfferTile(offer, isOutgoing: false)),
            const SizedBox(height: 8),
          ],

          // Regular transfer groups
          ...groups.map((group) => TransferCallsignGroupTile(
            group: group,
            selectionMode: _selectionMode,
            selectedIds: _selectedIds,
            onTransferSelected: _selectionMode ? _toggleSelection : null,
            onTransferTap: _showTransferDetails,
            onPause: !_selectionMode
                ? (t) => _service.pause(t.id)
                : null,
            onCancel: !_selectionMode ? _confirmCancel : null,
            initiallyExpanded: groups.length == 1,
          )),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildOfferTile(TransferOffer offer, {required bool isOutgoing}) {
    final theme = Theme.of(context);

    String statusText;
    Color statusColor;
    IconData statusIcon;

    switch (offer.status) {
      case TransferOfferStatus.pending:
        statusText = 'Waiting for acceptance';
        statusColor = Colors.orange;
        statusIcon = Icons.hourglass_empty;
        break;
      case TransferOfferStatus.accepted:
        statusText = isOutgoing ? 'Accepted, preparing...' : 'Starting download...';
        statusColor = Colors.blue;
        statusIcon = Icons.check_circle;
        break;
      case TransferOfferStatus.transferring:
        final percent = offer.progressPercent.toStringAsFixed(0);
        statusText = isOutgoing
            ? 'Uploading $percent%'
            : 'Downloading $percent%';
        statusColor = Colors.green;
        statusIcon = isOutgoing ? Icons.upload : Icons.download;
        break;
      default:
        statusText = offer.status.name;
        statusColor = Colors.grey;
        statusIcon = Icons.info;
    }

    final otherCallsign = isOutgoing
        ? offer.receiverCallsign ?? 'Unknown'
        : offer.senderCallsign;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: statusColor.withValues(alpha: 0.2),
          child: Icon(statusIcon, color: statusColor, size: 20),
        ),
        title: Text(
          '${isOutgoing ? "To" : "From"}: $otherCallsign',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              '${offer.totalFiles} files, ${_formatBytes(offer.totalBytes)}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(statusIcon, size: 12, color: statusColor),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    statusText,
                    style: theme.textTheme.bodySmall?.copyWith(color: statusColor),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (offer.status == TransferOfferStatus.transferring) ...[
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: offer.progressPercent / 100,
                backgroundColor: statusColor.withValues(alpha: 0.2),
                valueColor: AlwaysStoppedAnimation(statusColor),
              ),
            ],
          ],
        ),
        trailing: isOutgoing && offer.status == TransferOfferStatus.pending
            ? IconButton(
                icon: const Icon(Icons.cancel),
                onPressed: () => _cancelOffer(offer),
                tooltip: 'Cancel',
              )
            : null,
        isThreeLine: true,
      ),
    );
  }

  void _cancelOffer(TransferOffer offer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Offer'),
        content: Text('Cancel transfer to ${offer.receiverCallsign}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _p2pService.cancelOffer(offer.offerId);
      _refreshP2POffers();
    }
  }

  Widget _buildPreviousTab() {
    // Combine completed and failed transfers, sorted by timestamp (most recent first)
    // P2P transfers are now archived as regular Transfer records, so they appear here automatically
    final allPrevious = [
      ..._completedTransfers,
      ..._failedTransfers,
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (allPrevious.isEmpty) {
      return _buildEmptyState(
        'No previous transfers',
        'Completed and failed transfers will appear here',
        Icons.history,
      );
    }

    final groups = groupTransfersByCallsign(allPrevious);

    return RefreshIndicator(
      onRefresh: () async {
        await _refreshData();
        _refreshP2POffers();
      },
      child: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 80),
        children: [
          // Retry all failed button (only show if there are failed transfers)
          if (_failedTransfers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: FilledButton.icon(
                onPressed: () async {
                  await _service.retryAll();
                  _refreshData();
                },
                icon: const Icon(Icons.refresh),
                label: Text('Retry All Failed (${_failedTransfers.length})'),
              ),
            ),

          // All transfer groups (including P2P transfers which are now archived as Transfer records)
          ...groups.map((group) => TransferCallsignGroupTile(
            group: group,
            onTransferTap: _showTransferDetails,
            onRetry: (t) async {
              if (t.canRetry) {
                await _service.retry(t.id);
                _refreshData();
              }
            },
            onOpenFile: _openTransferFile,
            onOpenFolder: _openTransferFolder,
            onDelete: _deleteTransferFile,
            onCopyPath: _copyTransferPath,
            initiallyExpanded: groups.length == 1,
          )),
        ],
      ),
    );
  }

  Widget _buildStatsTab() {
    return RefreshIndicator(
      onRefresh: _refreshData,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 80),
        child: Column(
          children: [
            TransferMetricsCard(metrics: _metrics),
            TransferActivityChart(
              history: _historyPoints,
              periodStats: _metrics.today,
              onPeriodChanged: (period) {
                final history = _metricsService.getHistory(
                  period: period,
                  resolution: period.inDays <= 1
                      ? const Duration(hours: 1)
                      : const Duration(days: 1),
                );
                setState(() => _historyPoints = history);
              },
            ),
            TransportBreakdownChart(byTransport: _metrics.byTransport),
            _buildCallsignLeaderboard(),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _confirmClearAll(context),
                  icon: const Icon(Icons.delete_forever),
                  label: const Text('Clean all transfer data'),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCallsignLeaderboard() {
    final theme = Theme.of(context);

    if (_metrics.topCallsigns.isEmpty) {
      return const SizedBox();
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Top Transfer Partners',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            ..._metrics.topCallsigns
                .take(5)
                .map((stats) => _buildCallsignRow(stats)),
          ],
        ),
      ),
    );
  }

  Widget _buildCallsignRow(CallsignStats stats) {
    final theme = Theme.of(context);
    final index = _metrics.topCallsigns.indexOf(stats) + 1;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: index <= 3
                  ? [
                      Colors.amber,
                      Colors.grey,
                      Colors.brown,
                    ][index - 1].withOpacity(0.2)
                  : theme.colorScheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$index',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            stats.callsign,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.upload, size: 12, color: Colors.green),
          Text(' ${stats.uploadCount}', style: theme.textTheme.bodySmall),
          const SizedBox(width: 8),
          Icon(Icons.download, size: 12, color: Colors.blue),
          Text(' ${stats.downloadCount}', style: theme.textTheme.bodySmall),
          const Spacer(),
          Text(
            _formatBytes(stats.totalBytes),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String title, String subtitle, IconData icon) {
    final theme = Theme.of(context);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  void _showSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _SettingsSheet(
        settings: _service.settings,
        onSave: (settings) async {
          await _service.updateSettings(settings);
          _refreshData();
        },
        onClearAll: () async {
          await _service.clearAll();
          await _refreshData();
        },
      ),
    );
  }

  Future<void> _showTransferDetails(Transfer transfer) async {
    Map<String, dynamic>? record;
    try {
      record = await _service.getRecord(transfer.id);
    } catch (_) {
      record = null;
    }

    if (!mounted) return;

    final totalsByTransport = _extractTransportTotals(record, transfer);
    final createdAt =
        _parseTime(record?['created_at']) ?? transfer.createdAt.toLocal();
    final startedAt =
        _parseTime(record?['started_at']) ?? transfer.startedAt?.toLocal();
    final completedAt =
        _parseTime(record?['completed_at']) ?? transfer.completedAt?.toLocal();
    final duration = (startedAt != null && completedAt != null)
        ? completedAt.difference(startedAt)
        : null;

    final bytesTransferred =
        _asInt(record?['bytes_transferred']) ?? transfer.bytesTransferred;
    final expectedBytes =
        _asInt(record?['expected_bytes']) ?? transfer.expectedBytes;
    final transportUsed = record?['transport_used'] as String? ??
        transfer.transportUsed ??
        (totalsByTransport.isNotEmpty ? totalsByTransport.keys.first : null);

    final originUrl =
        transfer.remoteUrl ?? (record?['remote_url'] as String? ?? '');
    final origin = originUrl.isNotEmpty
        ? originUrl
        : transfer.sourceCallsign.isNotEmpty
            ? '${transfer.sourceCallsign}${transfer.remotePath}'
            : transfer.remotePath;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 12,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: theme.dividerColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        transfer.filename ?? 'Transfer details',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Chip(
                      label: Text(transfer.status.name),
                      backgroundColor:
                          theme.colorScheme.surfaceVariant.withOpacity(0.7),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'ID: ${transfer.id}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.link),
                  title: const Text('From'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(origin.isNotEmpty ? origin : 'Unknown'),
                      if (originUrl.isNotEmpty)
                        Text(
                          'HTTP/HTTPS URL',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        )
                      else if (transfer.sourceCallsign.isNotEmpty)
                        Text(
                          'Callsign ${transfer.sourceCallsign}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      if (transfer.remotePath.isNotEmpty)
                        Text(
                          'Remote path: ${transfer.remotePath}',
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.download_done),
                  title: const Text('Saving to'),
                  subtitle: Text(
                    transfer.localPath,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.route),
                  title: const Text('Transfer methods'),
                  subtitle: totalsByTransport.isNotEmpty
                      ? Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: totalsByTransport.entries
                              .map(
                                (entry) => Chip(
                                  label: Text(
                                    '${_formatTransportLabel(entry.key)}: ${_formatBytes(entry.value)}',
                                  ),
                                ),
                              )
                              .toList(),
                        )
                      : Text(
                          'Not recorded yet',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                ),
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.network_check),
                  title: const Text('Active transport'),
                  subtitle: Text(
                    _formatTransportLabel(transportUsed),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.storage),
                  title: const Text('Size'),
                  subtitle: Text(
                    '${_formatBytes(bytesTransferred)} of '
                    '${expectedBytes > 0 ? _formatBytes(expectedBytes) : 'unknown'}',
                  ),
                ),
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.access_time),
                  title: const Text('Timing'),
                  subtitle: Text(
                    [
                      if (createdAt != null)
                        'Created ${_formatTimestamp(createdAt)}',
                      if (startedAt != null)
                        'Started ${_formatTimestamp(startedAt)}',
                      if (completedAt != null)
                        'Finished ${_formatTimestamp(completedAt)}',
                      if (duration != null)
                        'Duration ${_formatDuration(duration)}',
                    ].join(' • '),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  void _confirmCancel(Transfer transfer) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Transfer'),
        content: Text('Cancel transfer of "${transfer.filename}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _service.cancel(transfer.id);
              _refreshData();
            },
            child: const Text('Cancel Transfer'),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // File action handlers for completed transfers
  // ─────────────────────────────────────────────────────────────────────────

  /// Check if a file extension is supported by internal viewers
  bool _isInternallySupported(String ext) {
    final lowerExt = ext.toLowerCase();
    // Images, videos, PDF, and editable text files
    return FileIconHelper.isImage('.$lowerExt') ||
        FileIconHelper.isVideo('.$lowerExt') ||
        lowerExt == 'pdf' ||
        DocumentViewerWidget.isEditableExtension(lowerExt);
  }

  /// Open a transferred file - internally for supported formats, system app otherwise
  void _openTransferFile(Transfer transfer) {
    final path = transfer.localPath;
    final ext = path.split('.').last.toLowerCase();

    if (_isInternallySupported(ext)) {
      _openInternalViewer(path, ext);
    } else {
      FileLauncherService().openFile(path);
    }
  }

  /// Route to the appropriate internal viewer
  void _openInternalViewer(String filePath, String ext) {
    final lowerExt = ext.toLowerCase();

    if (FileIconHelper.isImage('.$lowerExt') ||
        FileIconHelper.isVideo('.$lowerExt')) {
      // Open in photo/video viewer
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PhotoViewerPage(imagePaths: [filePath]),
        ),
      );
    } else {
      // Open in document viewer (PDF, text files, code, etc.)
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DocumentViewerEditorPage(filePath: filePath),
        ),
      );
    }
  }

  /// Open the containing folder of a transferred file
  void _openTransferFolder(Transfer transfer) {
    final dir = p.dirname(transfer.localPath);
    FileLauncherService().openFolder(dir);
  }

  /// Delete a transferred file with confirmation
  Future<void> _deleteTransferFile(Transfer transfer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete File'),
        content: Text('Delete "${transfer.filename}"?\n\nThis cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final file = File(transfer.localPath);
      if (await file.exists()) {
        await file.delete();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Deleted "${transfer.filename}"'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('File not found'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Copy the file path to clipboard
  void _copyTransferPath(Transfer transfer) {
    Clipboard.setData(ClipboardData(text: transfer.localPath));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Path copied to clipboard')),
    );
  }

  Future<void> _confirmClearAll(BuildContext context) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Clean all transfer data'),
            content: const Text(
              'This removes queue, records, metrics, and cache. Continue?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Keep data'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;
    await _service.clearAll();
    await _refreshData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Transfer data cleaned')),
      );
    }
  }

  Map<String, int> _extractTransportTotals(
    Map<String, dynamic>? record,
    Transfer transfer,
  ) {
    final totals =
        (record?['totals_by_transport'] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{};
    final result = <String, int>{};
    totals.forEach((key, value) {
      if (value is num) {
        result[key] = value.toInt();
      }
    });

    if (result.isEmpty && transfer.transportUsed != null) {
      result[transfer.transportUsed!] = transfer.bytesTransferred;
    }
    return result;
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }

  DateTime? _parseTime(dynamic value) {
    if (value is String) return DateTime.tryParse(value)?.toLocal();
    if (value is DateTime) return value.toLocal();
    return null;
  }

  String _formatTimestamp(DateTime? dt) {
    if (dt == null) return '—';
    final local = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return '—';
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) return '${hours}h ${minutes}m';
    if (minutes > 0) return '${minutes}m ${seconds}s';
    return '${seconds}s';
  }

  String _formatTransportLabel(String? id) {
    switch (id) {
      case 'internet_http':
      case 'station_http':
        return 'HTTP (TCP/IP)';
      case 'ble':
      case 'bluetooth':
        return 'BLE';
      case 'lora':
        return 'LoRa';
      case 'radio':
        return 'Radio';
      case null:
      case '':
        return 'Unknown';
      default:
        return id;
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

/// Settings bottom sheet
class _SettingsSheet extends StatefulWidget {
  final TransferSettings settings;
  final Future<void> Function(TransferSettings) onSave;
  final Future<void> Function() onClearAll;

  const _SettingsSheet({
    required this.settings,
    required this.onSave,
    required this.onClearAll,
  });

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  late TransferSettings _settings;
  final _banController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _settings = widget.settings.copyWith();
  }

  @override
  void dispose() {
    _banController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.9,
      minChildSize: 0.5,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.dividerColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text('Settings', style: theme.textTheme.titleLarge),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    await widget.onSave(_settings);
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
          const Divider(),
          // Content
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(16),
              children: [
                // Enabled toggle
                SwitchListTile(
                  title: const Text('Enable Transfers'),
                  subtitle: const Text(
                    'Process queued transfers automatically',
                  ),
                  value: _settings.enabled,
                  onChanged: (value) {
                    setState(
                      () => _settings = _settings.copyWith(enabled: value),
                    );
                  },
                ),
                const Divider(),

                // Concurrent transfers
                ListTile(
                  title: const Text('Concurrent Transfers'),
                  subtitle: Slider(
                    value: _settings.maxConcurrentTransfers.toDouble(),
                    min: 1,
                    max: 10,
                    divisions: 9,
                    label: '${_settings.maxConcurrentTransfers}',
                    onChanged: (value) {
                      setState(
                        () => _settings = _settings.copyWith(
                          maxConcurrentTransfers: value.round(),
                        ),
                      );
                    },
                  ),
                  trailing: Text('${_settings.maxConcurrentTransfers}'),
                ),

                // Max retries
                ListTile(
                  title: const Text('Max Retries'),
                  subtitle: Slider(
                    value: _settings.maxRetries.toDouble(),
                    min: 1,
                    max: 20,
                    divisions: 19,
                    label: '${_settings.maxRetries}',
                    onChanged: (value) {
                      setState(
                        () => _settings = _settings.copyWith(
                          maxRetries: value.round(),
                        ),
                      );
                    },
                  ),
                  trailing: Text('${_settings.maxRetries}'),
                ),

                const Divider(),

                // Ban list
                ListTile(
                  title: const Text('Banned Callsigns'),
                  subtitle: Text(
                    _settings.bannedCallsigns.isEmpty
                        ? 'No banned callsigns'
                        : '${_settings.bannedCallsigns.length} banned',
                  ),
                ),
                Wrap(
                  spacing: 8,
                  children: _settings.bannedCallsigns
                      .map(
                        (callsign) => Chip(
                          label: Text(callsign),
                          onDeleted: () {
                            setState(() {
                              final list = List<String>.from(
                                _settings.bannedCallsigns,
                              );
                              list.remove(callsign);
                              _settings = _settings.copyWith(
                                bannedCallsigns: list,
                              );
                            });
                          },
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _banController,
                        decoration: const InputDecoration(
                          labelText: 'Add callsign to ban',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        textCapitalization: TextCapitalization.characters,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: () {
                        final callsign = _banController.text
                            .trim()
                            .toUpperCase();
                        if (callsign.isNotEmpty &&
                            !_settings.bannedCallsigns.contains(callsign)) {
                          setState(() {
                            final list = List<String>.from(
                              _settings.bannedCallsigns,
                            );
                            list.add(callsign);
                            _settings = _settings.copyWith(
                              bannedCallsigns: list,
                            );
                            _banController.clear();
                          });
                        }
                      },
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                const Divider(),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                  ),
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Clean all transfer data'),
                            content: const Text(
                              'This removes queue, records, metrics, and cache. Continue?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Keep data'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                style: FilledButton.styleFrom(
                                  backgroundColor:
                                      theme.colorScheme.errorContainer,
                                ),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        ) ??
                        false;

                    if (!confirmed) return;
                    await widget.onClearAll();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Transfer data cleaned'),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.delete_forever),
                  label: const Text('Clean all transfer data'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
