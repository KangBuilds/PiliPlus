/// How many items before the end of a list its next page is asked for: about
/// a screen of cards or rows, so that the page is there before it is
/// scrolled to, instead of when the last item comes into view.
const int loadMoreAhead = 8;

/// Whether the item at [index] of a list of [length] is near enough to the
/// end to ask for the next page.
///
/// It holds for several items in a row, so it is only for loaders that do
/// nothing while a page is already on its way, like
/// `CommonController.onLoadMore`.
bool isNearEnd(int index, int length) => index >= length - loadMoreAhead;
