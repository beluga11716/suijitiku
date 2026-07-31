import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/theme/theme_color_type.dart';
import '../providers/settings_provider.dart';

class ThemeSettingsScreen extends StatelessWidget {
  const ThemeSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('选择主题颜色')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('选择一个主题色，应用内的强调色将随之改变',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.outline)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: List.generate(themeColorPresets.length, (i) {
              final preset = themeColorPresets[i];
              final isSelected = settings.themeColorIndex == i;
              final seedScheme = ColorScheme.fromSeed(
                seedColor: preset.color,
                brightness: theme.brightness,
              );
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => settings.setThemeColorIndex(i),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: seedScheme.primary,
                        border: isSelected
                            ? Border.all(
                                color: theme.colorScheme.onSurface, width: 2.5)
                            : null,
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: seedScheme.primary.withAlpha(100),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
                      ),
                      child: isSelected
                          ? const Icon(Icons.check, color: Colors.white, size: 22)
                          : null,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      preset.label,
                      style: TextStyle(
                        fontSize: 11,
                        color: isSelected
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.outline,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
