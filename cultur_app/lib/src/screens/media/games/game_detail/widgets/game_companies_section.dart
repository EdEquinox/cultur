import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:yamtrack/src/models/games/game_company_link.dart';
import 'package:yamtrack/src/screens/media/games/game_detail/widgets/game_company_group.dart';
import 'package:yamtrack/src/utils/catalog_utils.dart';

class GameCompaniesSection extends StatelessWidget {
  const GameCompaniesSection({
    super.key,
    required this.developers,
    required this.publishers,
  });

  final List<GameCompanyLink> developers;
  final List<GameCompanyLink> publishers;

  void _openCompany(BuildContext context, GameCompanyLink company, String role) {
    if (!company.isValid) {
      return;
    }
    context.push(
      gameCompanyDetailPath(
        companyId: company.companyId,
        role: role,
        name: company.name,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (developers.isEmpty && publishers.isEmpty) {
      return const SizedBox.shrink();
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (developers.isNotEmpty)
          Expanded(
            child: GameCompanyGroup(
              companies: developers,
              icon: Icons.code_outlined,
              onOpenCompany: (company) => _openCompany(context, company, 'developer'),
            ),
          ),
        if (developers.isNotEmpty && publishers.isNotEmpty) const SizedBox(width: 12),
        if (publishers.isNotEmpty)
          Expanded(
            child: GameCompanyGroup(
              companies: publishers,
              icon: Icons.business_outlined,
              onOpenCompany: (company) => _openCompany(context, company, 'publisher'),
            ),
          ),
      ],
    );
  }
}
