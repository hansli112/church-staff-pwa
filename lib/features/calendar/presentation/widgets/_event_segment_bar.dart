import 'package:flutter/material.dart';

import '_calendar_models.dart';

/// Renders a single event bar inside a calendar day cell.
///
/// Handles multi-day spanning (title shift + ClipRect) as well as
/// single-day events (normal Text with ellipsis).
class EventSegmentBar extends StatelessWidget {
  const EventSegmentBar({
    super.key,
    required this.segment,
    required this.maxLines,
    required this.cellWidth,
    required this.onTap,
  });

  final DayEventSegment segment;
  final int maxLines;
  final double cellWidth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isMultiDay = segment.event.spansMultipleDays;

    final textStyle = Theme.of(context).textTheme.labelSmall!.copyWith(
      fontWeight: FontWeight.w500,
      color: colorScheme.onPrimaryContainer,
    );

    final leadingInset = segment.continuesLeft ? 0.0 : 2.0;
    final trailingInset = segment.continuesRight ? 0.0 : 2.0;
    final leftTextInset = segment.continuesLeft ? 0.0 : 1.0;
    final rightTextInset = segment.continuesRight ? 0.0 : 1.0;
    final currentTextInset = leadingInset + leftTextInset;

    final borderRadius = BorderRadius.only(
      topLeft: Radius.circular(segment.continuesLeft ? 0 : 4),
      bottomLeft: Radius.circular(segment.continuesLeft ? 0 : 4),
      topRight: Radius.circular(segment.continuesRight ? 0 : 4),
      bottomRight: Radius.circular(segment.continuesRight ? 0 : 4),
    );

    final textWidget = Text(
      segment.event.title,
      maxLines: isMultiDay ? 1 : maxLines,
      softWrap: !isMultiDay,
      overflow: isMultiDay ? TextOverflow.visible : TextOverflow.ellipsis,
      style: textStyle,
    );

    final shouldShowTitle = segment.showTitle || isMultiDay;

    Widget content;
    if (shouldShowTitle) {
      if (isMultiDay) {
        final shift =
            (cellWidth * segment.titleShiftDays) +
            currentTextInset -
            segment.startTextInset;
        content = ClipRect(
          child: Transform.translate(
            offset: Offset(-shift, 0),
            child: textWidget,
          ),
        );
      } else {
        content = textWidget;
      }
    } else {
      content = Opacity(opacity: 0, child: textWidget);
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: borderRadius,
        onTap: onTap,
        child: Container(
          width: double.infinity,
          margin: EdgeInsets.only(
            left: leadingInset,
            right: trailingInset,
            bottom: 3,
          ),
          padding: EdgeInsets.fromLTRB(leftTextInset, 2, rightTextInset, 2),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withValues(alpha: 0.8),
            borderRadius: borderRadius,
          ),
          child: content,
        ),
      ),
    );
  }
}
