type PropertyPeriod = {
  entry_date: string | null;
  disposal_date: string | null;
};

export function isPropertyHeldAtPeriodEnd(
  property: PropertyPeriod,
  periodEnd: string,
) {
  return (
    (!property.entry_date || property.entry_date <= periodEnd) &&
    (!property.disposal_date || property.disposal_date > periodEnd)
  );
}

export function getPropertyPresentationAtPeriodEnd(
  property: PropertyPeriod,
  periodEnd: string,
) {
  const disposedDuringOrBeforePeriod = Boolean(
    property.disposal_date && property.disposal_date <= periodEnd,
  );

  return {
    status: disposedDuringOrBeforePeriod ? "Cédé" : "Actif",
    disposalDate: disposedDuringOrBeforePeriod ? property.disposal_date : null,
  } as const;
}
