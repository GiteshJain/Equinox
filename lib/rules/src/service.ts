// service: the service profile a route's flights take (the old planner's serviceFor; Reference → service profiles). An
// airline with a profile of its own (Ryanair's R) takes it on every route; every other airline takes the first of the
// shared profiles (no airline) whose "up to km" is more than the route's distance, in order of that distance, or the
// last of them on a longer route. The profiles are service_profiles' rows, given by the caller: they aren't part of
// rules_input().

/** A service_profiles row: its code, the airline it belongs to (none for the shared ones), and up to how many km. */
export interface ServiceProfile {
  id?: number;
  code: string;
  airline_id: number | null;
  up_to_km: number | null;
}

/** The profile a route of this airline and distance takes, or null when there's none to take. */
export function profileFor(profiles: readonly ServiceProfile[], airlineId: number, distanceKm: number | null | undefined): ServiceProfile | null {
  const byId = [...profiles].sort((a, b) => (a.id ?? 0) - (b.id ?? 0));
  const own = byId.find((p) => p.airline_id === airlineId);
  if (own) return own;
  const shared = byId.filter((p) => p.airline_id == null && p.up_to_km != null).sort((a, b) => (a.up_to_km ?? 0) - (b.up_to_km ?? 0));
  const km = distanceKm ?? 0;
  return shared.find((p) => km < (p.up_to_km ?? 0)) ?? shared[shared.length - 1] ?? null;
}
