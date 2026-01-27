import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import '../../services/storage_config.dart';
import '../../transfer/models/transfer_offer.dart';
import '../../transfer/services/p2p_transfer_service.dart';

/// Dialog shown when an incoming transfer offer is received
///
/// Displays:
/// - Sender information
/// - File list with sizes
/// - Destination folder selector
/// - Accept/Decline buttons
/// - Expiry countdown
class IncomingTransferDialog extends StatefulWidget {
  final TransferOffer offer;

  const IncomingTransferDialog({
    super.key,
    required this.offer,
  });

  /// Show the dialog and return true if accepted, false if declined
  static Future<bool?> show(BuildContext context, TransferOffer offer) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => IncomingTransferDialog(offer: offer),
    );
  }

  @override
  State<IncomingTransferDialog> createState() => _IncomingTransferDialogState();
}

class _IncomingTransferDialogState extends State<IncomingTransferDialog> {
  late String _destinationPath;
  bool _isAccepting = false;

  @override
  void initState() {
    super.initState();
    // Default to Downloads/Transfers folder
    _destinationPath = path.join(
      StorageConfig().baseDir,
      'Downloads',
      'Transfers',
      widget.offer.senderCallsign,
    );
  }

  Future<void> _selectDestination() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select destination folder',
      initialDirectory: _destinationPath,
    );

    if (result != null && mounted) {
      setState(() => _destinationPath = result);
    }
  }

  Future<void> _accept() async {
    setState(() => _isAccepting = true);

    try {
      await P2PTransferService().acceptOffer(
        widget.offer.offerId,
        _destinationPath,
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
        setState(() => _isAccepting = false);
      }
    }
  }

  Future<void> _decline() async {
    await P2PTransferService().rejectOffer(widget.offer.offerId);
    if (mounted) {
      Navigator.of(context).pop(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.file_download,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 12),
          const Text('Incoming File Transfer'),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sender info
            _buildSenderInfo(theme),
            const SizedBox(height: 16),

            // File list
            _buildFileList(theme),
            const SizedBox(height: 16),

            // Summary
            _buildSummary(theme),
            const SizedBox(height: 16),

            // Destination selector
            _buildDestinationSelector(theme),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isAccepting ? null : _decline,
          child: const Text('Decline'),
        ),
        FilledButton.icon(
          onPressed: _isAccepting ? null : _accept,
          icon: _isAccepting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.download),
          label: const Text('Accept & Download'),
        ),
      ],
    );
  }

  Widget _buildSenderInfo(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Text(
              widget.offer.senderCallsign.isNotEmpty
                  ? widget.offer.senderCallsign[0]
                  : '?',
              style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'From:',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  widget.offer.senderCallsign,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileList(ThemeData theme) {
    final files = widget.offer.files;
    final displayCount = files.length > 5 ? 5 : files.length;
    final hasMore = files.length > 5;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Files:',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          constraints: const BoxConstraints(maxHeight: 150),
          decoration: BoxDecoration(
            border: Border.all(color: theme.dividerColor),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: displayCount + (hasMore ? 1 : 0),
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              if (hasMore && index == displayCount) {
                return Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    '... and ${files.length - displayCount} more files',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                );
              }

              final file = files[index];
              return ListTile(
                dense: true,
                leading: Icon(
                  _getFileIcon(file.name),
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                title: Text(
                  file.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                trailing: Text(
                  _formatBytes(file.size),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSummary(ThemeData theme) {
    final timeRemaining = widget.offer.timeUntilExpiry;
    final minutes = timeRemaining.inMinutes;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          '${widget.offer.totalFiles} files, ${_formatBytes(widget.offer.totalBytes)}',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: minutes < 5
                ? theme.colorScheme.errorContainer
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            minutes > 60
                ? 'Expires in ${timeRemaining.inHours}h ${minutes % 60}m'
                : 'Expires in ${minutes}m',
            style: theme.textTheme.labelSmall?.copyWith(
              color: minutes < 5
                  ? theme.colorScheme.onErrorContainer
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDestinationSelector(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Save to:',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: _selectDestination,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: theme.dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.folder,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _destinationPath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _selectDestination,
                  child: const Text('Browse'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  IconData _getFileIcon(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
      case 'bmp':
        return Icons.image;
      case 'mp4':
      case 'avi':
      case 'mov':
      case 'mkv':
      case 'webm':
        return Icons.video_file;
      case 'mp3':
      case 'wav':
      case 'flac':
      case 'ogg':
      case 'aac':
        return Icons.audio_file;
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
      case 'txt':
      case 'rtf':
        return Icons.description;
      case 'zip':
      case 'rar':
      case 'tar':
      case 'gz':
      case '7z':
        return Icons.folder_zip;
      default:
        return Icons.insert_drive_file;
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
