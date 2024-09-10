import 'dart:async';

import 'package:graphql/client.dart';

import 'package:graphql/src/core/_query_write_handling.dart';

/// Fetch more results and then merge them with [previousResult]
/// according to [FetchMoreOptions.updateQuery]
///
/// Will add results if [ObservableQuery.queryId] is supplied,
/// and broadcast any cache changes
///
/// This is the **Internal Implementation**,
/// used by [ObservableQuery] and [GraphQLCLient.fetchMore]
Future<QueryResult<TParsed>> fetchMoreImplementation<TParsed>(
  FetchMoreOptions fetchMoreOptions, {
  required QueryOptions<TParsed> originalOptions,
  required QueryManager queryManager,
  required QueryResult<TParsed> previousResult,
  String? queryId,
}) async {
  // fetch more and update

  final request = originalOptions.asRequest;

  final combinedOptions =
      originalOptions.withFetchMoreOptions(fetchMoreOptions);

  QueryResult<TParsed> fetchMoreResult =
      await queryManager.query(combinedOptions);

  try {
    // combine the query with the new query, using the function provided by the user
    final data = fetchMoreOptions.updateQuery(
      previousResult.data,
      fetchMoreResult.data,
    );

    fetchMoreResult.data = data;

    if (originalOptions.fetchPolicy != FetchPolicy.noCache && data != null) {
      queryManager.attemptCacheWriteFromClient(
        request,
        data,
        fetchMoreResult,
        writeQuery: (req, data) => queryManager.cache.writeQuery(
          req,
          data: data!,
        ),
      );
    }

    // will add to a stream with `queryId` and rebroadcast if appropriate
    queryManager.addQueryResult(
      request,
      queryId,
      fetchMoreResult,
    );
  } catch (error) {
    if (fetchMoreResult.hasException) {
      // because the updateQuery failure might have been because of these errors,
      // we just add them to the old errors
      previousResult.exception = coalesceErrors(
        exception: previousResult.exception,
        graphqlErrors: fetchMoreResult.exception!.graphqlErrors,
        linkException: fetchMoreResult.exception!.linkException,
      );
      return previousResult;
    } else {
      // TODO merge results OperationException
      rethrow;
    }
  }

  return fetchMoreResult;
}
