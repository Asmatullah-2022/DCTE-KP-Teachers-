// This project has no default counter-app widget to test — the generated
// Android platform files (see .github/workflows/build-apk.yml) would
// otherwise create a stock widget_test.dart referencing a nonexistent
// `MyApp` class. Committing this file prevents that overwrite and keeps
// `flutter analyze`/`flutter test` meaningful instead of failing on a
// leftover template reference.
import 'package:flutter_test/flutter_test.dart';
import 'package:dcte_kp_teachers/core/constants/app_constants.dart';

void main() {
  test('app name constant is set', () {
    expect(AppConstants.appName, isNotEmpty);
  });
}
