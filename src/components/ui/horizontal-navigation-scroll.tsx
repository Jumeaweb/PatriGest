"use client";

import { useLayoutEffect, useRef, type ReactNode } from "react";
import { getScrollLeftToRevealItem } from "./horizontal-navigation-scroll-position";

export function HorizontalNavigationScroll({
  activeKey,
  children,
  className = "",
}: {
  activeKey: string;
  children: ReactNode;
  className?: string;
}) {
  const viewportRef = useRef<HTMLDivElement>(null);

  useLayoutEffect(() => {
    const currentViewport = viewportRef.current;
    if (!currentViewport) return;
    const viewport: HTMLDivElement = currentViewport;
    let animationFrame = 0;
    let cancelled = false;

    function revealActiveItem() {
      const activeItem = viewport.querySelector<HTMLElement>('[aria-current="page"]');
      if (!activeItem) return;
      const viewportBounds = viewport.getBoundingClientRect();
      const itemBounds = activeItem.getBoundingClientRect();
      const nextScrollLeft = getScrollLeftToRevealItem({
        viewportLeft: viewportBounds.left,
        viewportRight: viewportBounds.right,
        itemLeft: itemBounds.left,
        itemRight: itemBounds.right,
        currentScrollLeft: viewport.scrollLeft,
        maxScrollLeft: viewport.scrollWidth - viewport.clientWidth,
      });
      if (nextScrollLeft !== viewport.scrollLeft) viewport.scrollLeft = nextScrollLeft;
    }

    function scheduleReveal() {
      cancelAnimationFrame(animationFrame);
      animationFrame = requestAnimationFrame(revealActiveItem);
    }

    revealActiveItem();
    scheduleReveal();
    document.fonts?.ready.then(() => {
      if (!cancelled) scheduleReveal();
    });

    const observer = typeof ResizeObserver === "undefined" ? null : new ResizeObserver(scheduleReveal);
    observer?.observe(viewport);
    const rail = viewport.firstElementChild;
    if (rail) observer?.observe(rail);
    window.addEventListener("resize", scheduleReveal);
    return () => {
      cancelled = true;
      cancelAnimationFrame(animationFrame);
      observer?.disconnect();
      window.removeEventListener("resize", scheduleReveal);
    };
  }, [activeKey]);

  return <div
    ref={viewportRef}
    className={`max-w-full overflow-x-auto overscroll-x-contain [-ms-overflow-style:none] [scrollbar-width:none] [&::-webkit-scrollbar]:hidden ${className}`}
  >{children}</div>;
}
