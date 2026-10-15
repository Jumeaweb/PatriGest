export type HorizontalScrollBounds = {
  viewportLeft: number;
  viewportRight: number;
  itemLeft: number;
  itemRight: number;
  currentScrollLeft: number;
  maxScrollLeft?: number;
  gutter?: number;
};

export function getScrollLeftToRevealItem({
  viewportLeft,
  viewportRight,
  itemLeft,
  itemRight,
  currentScrollLeft,
  maxScrollLeft = Number.POSITIVE_INFINITY,
  gutter = 8,
}: HorizontalScrollBounds) {
  if (itemLeft < viewportLeft + gutter) {
    return Math.max(0, currentScrollLeft + itemLeft - viewportLeft - gutter);
  }
  if (itemRight > viewportRight - gutter) {
    return Math.min(maxScrollLeft, currentScrollLeft + itemRight - viewportRight + gutter);
  }
  return currentScrollLeft;
}
