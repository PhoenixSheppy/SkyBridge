import 'dart:async';
import 'dart:io';

import 'package:bluesky/bluesky.dart' as bsky;
import 'package:dart_frog/dart_frog.dart';
import 'package:sky_bridge/database.dart';
import 'package:sky_bridge/models/database/id_pairs.dart';
import 'package:sky_bridge/models/mastodon/mastodon_account.dart';
import 'package:sky_bridge/models/mastodon/mastodon_post.dart';
import 'package:sky_bridge/models/params/statuses_params.dart';
import 'package:sky_bridge/util.dart';

Future<Response> onRequest(RequestContext context, String id) async {
  final params = context.request.uri.queryParameters;
  final options = StatusesParams.fromJson(params);

  final connection = await session;
  final bluesky = bsky.Bluesky.fromSession(
    connection,
  );

  final user = await db.dIDPairs.get(int.parse(id));
  if (user == null) {
    return Response(statusCode: HttpStatus.notFound);
  }

  // Get the users profile.
  final profile = await bluesky.actors.findProfile(actor: user.did);
  final profileInfo = ProfileInfo.fromActorProfile(profile.data);

  // Get the users posts.
  final feed = await bluesky.feeds.findFeed(actor: user.did, limit: 40);

  // Get all accounts that are in the feed and add them to the database.
  final accounts = feed.data.feed.map((view) => view.post.author).toList();

  // Mark down any new posts we see in the database.
  final pairs = await markDownFeedView(feed.data.feed)
  ..addAll(await markDownAccounts(accounts));

  // Take all the posts and convert them to Mastodon ones
  final posts = feed.data.feed.map((view) {
    return MastodonPost.fromFeedView(view, pairs, profile: profileInfo);
  }).toList();

  final exclude = options.excludeReblogs;
  if (exclude) {
    // Remove all posts that are reposts
    posts.removeWhere((post) => post.account.username != connection.handle);
  }

  return Response.json(
    body: posts,
  );
}
