import type { Category } from "@/types/database";

export type OfficialCategoryGroup = {
  label: string;
  categories: Category[];
};

export function groupOfficialCategories(categories: Category[]): OfficialCategoryGroup[] {
  const groups = new Map<string, Category[]>();
  const officialCategories = categories
    .filter((category) => category.is_system && category.official_code && category.official_group)
    .sort((left, right) =>
      (left.official_order ?? Number.MAX_SAFE_INTEGER) - (right.official_order ?? Number.MAX_SAFE_INTEGER)
      || (left.official_code ?? "").localeCompare(right.official_code ?? ""),
    );

  for (const category of officialCategories) {
    const label = category.official_group!;
    groups.set(label, [...(groups.get(label) ?? []), category]);
  }

  return [...groups].map(([label, groupedCategories]) => ({
    label,
    categories: groupedCategories,
  }));
}
