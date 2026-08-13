import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/theme/app_theme.dart';

/// "О приложении" — author credit, license, and a short in-app usage
/// guide, reachable from the Устройства tab. Nothing here reads from
/// providers/repositories — it's static reference content, not app state.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('О приложении')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
        children: [
          const Center(
            child: Column(
              children: [
                Icon(Icons.graphic_eq, size: 56, color: AppTheme.accent),
                SizedBox(height: 8),
                Text('audiloc', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                SizedBox(height: 4),
                _VersionLabel(),
                SizedBox(height: 8),
                Text('Автор: zaigard', style: TextStyle(color: AppTheme.onSurfaceMuted)),
                SizedBox(height: 8),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    'Лицензия: PolyForm Noncommercial 1.0.0 — свободно для любых '
                    'некоммерческих целей; коммерческое использование — по '
                    'отдельному разрешению автора.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.onSurfaceMuted, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          const Divider(),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Как пользоваться', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          const _GuideSection(
            title: 'Библиотека',
            body: 'Импортируйте папку или отдельные файлы — теги и обложки '
                'подтянутся автоматически, повторный импорт того же файла не '
                'создаёт дубль. Долгий тап по треку (на десктопе — правый клик) '
                'открывает меню: редактировать (название/исполнитель/альбом/'
                'жанр/обложку), добавить в плейлист, поделиться, удалить. '
                'Удаление — не безвозвратное: трек попадает в «Удалённые» '
                '(вкладка «Плейлисты»), откуда его можно вернуть или стереть '
                'по-настоящему.',
          ),
          const _GuideSection(
            title: 'Плейлисты',
            body: 'Кнопка «+» создаёт новый плейлист. Внутри плейлиста кнопка '
                'добавления треков открывает поиск с множественным выбором — '
                'можно отметить сразу несколько и добавить их одной кнопкой. '
                'Долгий тап (правый клик) по плейлисту в сетке — переименовать, '
                'удалить или выбрать обложку (одну из обложек его же треков или '
                'картинку из файла). «Избранное» и «Удалённые» — отдельные '
                'встроенные карточки в той же сетке.',
          ),
          const _GuideSection(
            title: 'Устройства и сопряжение',
            body: 'Устройства поблизости в локальной сети видны сами, без '
                'настройки — на вкладке «Устройства» под заголовком «Найдено '
                'рядом». «Добавить» отправляет запрос на сопряжение; на другом '
                'устройстве нужно подтвердить его («Разрешить»). Сопряжение '
                'работает только внутри одного и того же профиля — если нужно '
                'передать что-то в другой профиль (в том числе чужой), '
                'используйте «Поделиться» вместо сопряжения.',
          ),
          const _GuideSection(
            title: '«Поделиться»',
            body: 'В меню трека пункт «Поделиться» отправляет этот трек (или, по '
                'желанию, весь его альбом) любому видимому поблизости устройству '
                '— даже не сопряжённому и с другим профилем. Принимающая сторона '
                'видит название и обложку и сама решает, принять ли — просто '
                'скачивается и добавляется в библиотеку, без слияния профилей.',
          ),
          const _GuideSection(
            title: 'Профили',
            body: 'Несколько человек могут делить одно устройство — у каждого '
                'своя библиотека и свой список сопряжённых устройств; '
                'переключение — карточка профиля на вкладке «Устройства» → '
                '«Сменить». Если это, наоборот, второе устройство одного и того '
                'же человека — кнопка «Ждать сопряжения» (при создании профиля '
                'или из переключателя) делает его копией уже существующего. '
                'Удаление профиля необратимо и требует ввода его имени для '
                'подтверждения; удалить можно только неактивный профиль.',
          ),
        ],
      ),
    );
  }
}

class _VersionLabel extends StatelessWidget {
  const _VersionLabel();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final info = snapshot.data;
        return Text(
          info == null ? ' ' : 'Версия ${info.version}',
          style: const TextStyle(color: AppTheme.onSurfaceMuted),
        );
      },
    );
  }
}

class _GuideSection extends StatelessWidget {
  const _GuideSection({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(body, style: const TextStyle(color: AppTheme.onSurfaceMuted)),
      ],
    );
  }
}
