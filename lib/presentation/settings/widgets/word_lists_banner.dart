import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:voca/presentation/base/base_theme.dart';
import 'package:voca/presentation/base/l10n/gen/strings.g.dart';
import 'package:voca/presentation/base/routing/routers/main/main_router.dart';
import 'package:voca/presentation/base/widgets/base_card.dart';

class WordListsBanner extends StatelessWidget {
  const WordListsBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return BaseCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t.settings.words,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeights.bold,
            ),
          ),
          const SizedBox(height: 10),
          buildLearningButton(context),
        ],
      ),
    );
  }

  Widget buildLearningButton(BuildContext context) {
    final t = Translations.of(context);

    return OutlinedButton(
      onPressed: () {
        debugPrint('pushing learningListRoute');

        final router = AutoRouter.of(context);
        router.push(const LearningListRoute());

        debugPrint('stack: ${router.stack}');
      },
      style: ButtonStyle(
          backgroundColor: MaterialStatePropertyAll(BaseColors.curiousBlue10),
          alignment: Alignment.center,
          side: const MaterialStatePropertyAll(BorderSide(
            width: 2,
            color: BaseColors.curiousBlue,
          ))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            t.common.learning,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeights.medium,
              color: BaseColors.curiousBlue,
            ),
          ),
        ],
      ),
    );
  }
}
