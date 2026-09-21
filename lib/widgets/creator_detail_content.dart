import 'package:cached_network_image/cached_network_image.dart';
import 'package:cf_map_flutter/widgets/favorite_button.dart';
import 'package:cf_map_flutter/widgets/sample_works_gallery.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/creator.dart';
import '../services/analytics_service.dart';
import '../services/recommendation_service.dart';
import '../utils/url_encoding.dart';
import '../design_system/cf_design_system.dart';

class CreatorDetailContent extends StatefulWidget {
  final Creator creator;
  final bool showFavoriteButton;
  final bool showShareButton;
  final bool showCloseButton;
  final VoidCallback? onClose;
  final Function(String) onRequestSearch;

  const CreatorDetailContent({
    super.key,
    required this.creator,
    this.showFavoriteButton = false,
    this.showShareButton = true,
    this.showCloseButton = false,
    this.onClose,
    required this.onRequestSearch,
  });

  @override
  State<CreatorDetailContent> createState() => _CreatorDetailContentState();
}

class _CreatorDetailContentState extends State<CreatorDetailContent> {
  bool isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _headerSection(context),
          const SizedBox(height: 16),

          Row(
            children: [
              Icon(Icons.calendar_today,
                  color: _getDayColor(widget.creator.day), size: 20),
              const SizedBox(width: 8),
              Text(
                widget.creator.dayDisplay,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _getDayColor(widget.creator.day),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // URLs
          if (widget.creator.links.isNotEmpty) ...[
            const CfKicker('Creator links'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.creator.links.map((link) {
                return Tooltip(
                  message: link.url,
                  child: CfTag(
                    icon: Icons.link,
                    label: link.title.isNotEmpty ? link.title : link.url,
                    color: context.cf.cyan.withValues(alpha: 0.22),
                    onTap: () {
                      umami.trackEvent(
                        name: 'creator_link_tapped',
                        data: {
                          'creator_id': widget.creator.id.toString(),
                          'creator_name': widget.creator.name,
                          'link_title': link.title,
                          'link_url': link.url,
                        },
                      );
                      context
                          .read<RecommendationService>()
                          .recordExternalLinkOpened(widget.creator);
                      try {
                        launchUrl(Uri.parse(link.url),
                            mode: LaunchMode.externalApplication);
                      } catch (_) {}
                    },
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 18),
          ],

          // Fandom
          if (widget.creator.fandoms.isNotEmpty) ...[
            CfKicker(
              'Fandom${widget.creator.fandoms.length > 1 ? 's' : ''}',
              color: context.cf.pink,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.creator.fandoms.map((fandom) {
                return CfTag(
                  icon: Icons.favorite,
                  label: fandom.name,
                  color: context.cf.pink.withValues(alpha: 0.2),
                  onTap: () {
                    umami.trackEvent(
                      name: 'fandom_tapped',
                      data: {
                        'creator_id': widget.creator.id.toString(),
                        'creator_name': widget.creator.name,
                        'source': 'creator_detail',
                        'fandom_id': fandom.id.toString(),
                        'fandom': fandom.name,
                      },
                    );
                    context
                        .read<RecommendationService>()
                        .recordFandomInterest(fandom.id);
                    widget.onRequestSearch(fandom.name);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 18),
          ],

          // Works Type
          if (widget.creator.offerings.isNotEmpty) ...[
            CfKicker(
              'Works type${widget.creator.offerings.length > 1 ? 's' : ''}',
              color: context.cf.violet,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.creator.offeringNames.map((worksType) {
                return CfTag(
                  icon: Icons.sell,
                  label: worksType,
                  color: context.cf.violet.withValues(alpha: 0.18),
                );
              }).toList(),
            ),
            const SizedBox(height: 18),
          ],

          // Booths
          CfKicker(
            'Booth location${widget.creator.booths.length > 1 ? 's' : ''}',
            color: context.cf.yellow,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.creator.booths.map((booth) {
              return CfTag(
                icon: Icons.location_on,
                label: booth,
                color: context.cf.yellow,
              );
            }).toList(),
          ),

          const SizedBox(height: 32)
        ],
      ),
    );
  }

  ClipRRect _headerSection(BuildContext context) {
    final theme = Theme.of(context);

    return ClipRRect(
      borderRadius: const BorderRadius.all(Radius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              _CircleCut(creator: widget.creator, isExpanded: isExpanded),
              Positioned(
                top: 0,
                left: 0,
                child: Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLow
                        .withValues(alpha: 0.8),
                    borderRadius: const BorderRadius.all(Radius.circular(32)),
                    border: Border.all(
                        color:
                            theme.colorScheme.outline.withValues(alpha: 0.3)),
                  ),
                  child: IconButton(
                    icon: isExpanded
                        ? const Icon(Icons.fullscreen_exit)
                        : const Icon(Icons.fullscreen),
                    tooltip: isExpanded
                        ? 'Collapse Circle Cut'
                        : 'Expand Circle Cut',
                    onPressed: () {
                      umami.trackEvent(
                        name: 'creator_circle_cut_expand_tapped',
                        data: {
                          'creator_id': widget.creator.id.toString(),
                          'creator_name': widget.creator.name,
                          'expanded': (!isExpanded).toString(),
                        },
                      );
                      setState(() => isExpanded = !isExpanded);
                    },
                  ),
                ),
              ),
              Positioned(
                top: 0,
                right: 0,
                child: CreatorDetailActions(
                  creator: widget.creator,
                  showFavoriteButton: widget.showFavoriteButton,
                  showShareButton: widget.showShareButton,
                  showCloseButton: widget.showCloseButton,
                  onClose: widget.onClose,
                  onShare: () => shareCreator(context, widget.creator),
                ),
              )
            ],
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                const CfKicker('Circle profile'),
                const SizedBox(height: 6),
                Text(
                  widget.creator.name,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (widget.creator.circlePageUrl != null)
                      CfActionButton(
                        icon: Icons.open_in_new,
                        label: 'Wibuvent Page',
                        compact: true,
                        color: context.cf.yellow,
                        onPressed: () {
                          umami.trackEvent(
                            name: 'creator_circle_page_link_tapped',
                            data: {
                              'creator_id': widget.creator.id.toString(),
                              'creator_name': widget.creator.name,
                            },
                          );
                          context
                              .read<RecommendationService>()
                              .recordExternalLinkOpened(widget.creator);
                          launchUrl(
                            Uri.parse(widget.creator.circlePageUrl!),
                            mode: LaunchMode.externalApplication,
                          );
                        },
                      ),
                    if (widget.creator.assets.gallery.isNotEmpty)
                      CfActionButton(
                        icon: widget.creator.assets.gallery.length > 1
                            ? Icons.photo_library
                            : Icons.photo,
                        label:
                            'Samplework${widget.creator.assets.gallery.length > 1 ? 's' : ''}',
                        compact: true,
                        color: context.cf.cyan,
                        onPressed: () {
                          umami.trackEvent(
                            name: 'creator_sampleworks_tapped',
                            data: {
                              'creator_id': widget.creator.id.toString(),
                              'creator_name': widget.creator.name,
                              'count': widget.creator.assets.gallery.length
                                  .toString(),
                            },
                          );
                          showSampleWorksGallery(
                            context: context,
                            imageUrls: widget.creator.assets.gallery,
                            creator: widget.creator,
                          );
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getDayColor(String day) {
    switch (day) {
      case 'BOTH':
        return Colors.purple;
      case 'SAT':
        return Colors.blue;
      case 'SUN':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }
}

class CreatorDetailActions extends StatelessWidget {
  const CreatorDetailActions({
    super.key,
    required this.creator,
    required this.showFavoriteButton,
    required this.showShareButton,
    required this.showCloseButton,
    required this.onShare,
    this.onClose,
  });

  final Creator creator;
  final bool showFavoriteButton;
  final bool showShareButton;
  final bool showCloseButton;
  final VoidCallback onShare;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        if (showFavoriteButton || showShareButton)
          Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color:
                  theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.88),
              borderRadius: const BorderRadius.all(Radius.circular(32)),
              border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                if (showFavoriteButton)
                  FavoriteButton(key: Key(creator.name), creator: creator),
                if (showShareButton)
                  IconButton(
                    icon: const Icon(Icons.share),
                    tooltip: 'Share',
                    onPressed: () {
                      umami.trackEvent(
                        name: 'creator_share_tapped',
                        data: {
                          'creator_id': creator.id.toString(),
                          'creator_name': creator.name,
                        },
                      );
                      onShare();
                    },
                  ),
              ],
            ),
          ),
        if (showCloseButton && onClose != null)
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: const BorderRadius.all(Radius.circular(32)),
              border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.3),
              ),
            ),
            child: IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Close',
              onPressed: () {
                umami.trackEvent(
                  name: 'mobile_creator_detail_dismiss_tapped',
                  data: {
                    'creator_id': creator.id.toString(),
                    'creator_name': creator.name,
                  },
                );
                onClose?.call();
              },
            ),
          ),
      ],
    );
  }
}

Future<void> shareCreator(BuildContext context, Creator creator) async {
  if (creator.id == -1) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
            'Share feature is currently unavailable. We\'ll add this back as soon as we can!',
            style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 3),
      ),
    );
    return;
  }

  try {
    final shareUrl = UrlEncoding.toUrl({'creator_id': creator.id});

    await Clipboard.setData(ClipboardData(text: shareUrl));
    if (context.mounted) {
      context.read<RecommendationService>().recordCreatorShared(creator);
    }

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Link copied: ${creator.name}',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Could not copy link.'),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 3),
      ),
    );
  }
}

class _CircleCut extends StatefulWidget {
  final Creator creator;
  final bool isExpanded;

  const _CircleCut({required this.creator, required this.isExpanded});

  @override
  State<_CircleCut> createState() => _CircleCutState();
}

class _CircleCutState extends State<_CircleCut> {
  @override
  Widget build(BuildContext context) {
    final targetAspectRatio = widget.isExpanded ? 0.7 : 2.0;
    final targetScale = widget.isExpanded ? 1.0 : 1.1;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: targetAspectRatio, end: targetAspectRatio),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      builder: (context, aspect, child) {
        return AspectRatio(
          aspectRatio: aspect,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: targetScale, end: targetScale),
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            builder: (context, scale, _) {
              return Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                ),
                child: ClipRect(
                  child: Transform.scale(
                    scale: scale,
                    alignment: Alignment.bottomCenter,
                    child: CachedNetworkImage(
                      imageUrl: widget.creator.assets.thumbnail ?? '',
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        color:
                            _getSectionColor(_getBoothSection(widget.creator)),
                      ),
                      errorWidget: (context, url, error) => Container(
                        color:
                            _getSectionColor(_getBoothSection(widget.creator)),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  String _getBoothSection(Creator creator) {
    if (creator.booths.isEmpty) return '?';
    final firstBooth = creator.booths.first;
    final hyphen = firstBooth.indexOf('-');
    if (hyphen > 0) {
      return firstBooth.substring(0, hyphen).toUpperCase();
    }
    return firstBooth.isNotEmpty
        ? firstBooth.substring(0, 1).toUpperCase()
        : '?';
  }

  Color _getSectionColor(String section) {
    const List<Color> palette = [
      Color(0xFF1976D2), // blue 700
      Color(0xFF388E3C), // green 600
      Color(0xFFEF6C00), // orange 800
      Color(0xFF7B1FA2), // purple 700
      Color(0xFFD32F2F), // red 700
      Color(0xFF00838F), // cyan 800
      Color(0xFF558B2F), // light green 700
      Color(0xFFFF8F00), // amber 800
    ];
    final idx = section.codeUnitAt(0) % palette.length;
    return palette[idx];
  }
}
