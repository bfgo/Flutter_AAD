import 'package:aad_oauth/helper/core_oauth.dart';
import 'package:aad_oauth/model/config.dart';

CoreOAuth getOAuthConfig(NavigatorConfig config) => CoreOAuth.fromConfig(config);
