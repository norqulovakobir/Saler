import 'package:flutter/material.dart';

import '../l10n.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

/// Xaridorning saqlangan bildirishnomalari.
///
/// Serverda sotuvchi uchun alohida xabarnoma oqimi bor. Bu ekran esa xaridor
/// telefoniga kelgan jonli ilova xabarlarini saqlaydi va qayta ochib ko'rishga
/// imkon beradi.
class BuyerNotificationsScreen extends StatefulWidget {
  const BuyerNotificationsScreen({super.key});

  @override
  State<BuyerNotificationsScreen> createState() =>
      _BuyerNotificationsScreenState();
}

class _BuyerNotificationsScreenState extends State<BuyerNotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppState.instance.markNoticesRead();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(tr('Bildirishnomalar')),
          actions: [
            ListenableBuilder(
              listenable: AppState.instance,
              builder: (_, __) {
                if (AppState.instance.notices.isEmpty) {
                  return const SizedBox.shrink();
                }
                return IconButton(
                  tooltip: tr('Tozalash'),
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: AppState.instance.clearNotices,
                );
              },
            ),
            const SizedBox(width: 6),
          ],
        ),
        body: ListenableBuilder(
          listenable: AppState.instance,
          builder: (_, __) {
            final notices = AppState.instance.notices;
            if (notices.isEmpty) {
              return EmptyBox(Icons.notifications_none_rounded,
                  tr("Hozircha bildirishnoma yo'q"));
            }
            final p = context.p;
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, navPad),
              itemCount: notices.length,
              separatorBuilder: (_, __) => const SizedBox(height: 9),
              itemBuilder: (_, index) {
                final notice = notices[index];
                return Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: p.card,
                    borderRadius: BorderRadius.circular(18),
                    border: context.isDark
                        ? Border.all(color: p.border)
                        : Border.all(color: p.border),
                    boxShadow: softShadow(context, y: 5, blur: 16, a: .035),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                            color: p.accentSoft,
                            borderRadius: BorderRadius.circular(13)),
                        child: Icon(Icons.notifications_none_rounded,
                            color: p.accentText, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Expanded(
                                child: Text(notice.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14)),
                              ),
                              Text(fmtTime(notice.createdAt),
                                  style: TextStyle(
                                      color: p.muted,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 11)),
                            ]),
                            if (notice.body.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(notice.body,
                                  style: TextStyle(
                                      color: p.muted,
                                      height: 1.35,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      );
}
