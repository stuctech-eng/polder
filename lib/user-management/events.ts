import type { SupabaseClient } from "@supabase/supabase-js";
import type { DomainEventType } from "@/lib/events/types";

/**
 * Volgt het patroon dat overal in de app daadwerkelijk gebruikt wordt: directe
 * insert in domain_events, niet de ongebruikte EventBus-class (zie sectie 10.7
 * bevindingen in docs/architecture.md — bewuste keuze, geen omissie).
 */
export async function publishUserEvent(
  supabase: SupabaseClient,
  params: {
    restaurantId: string;
    eventType: Extract<
      DomainEventType,
      "UserInvited" | "UserRoleChanged" | "UserActivated" | "UserDeactivated"
    >;
    payload: Record<string, unknown>;
    publishedBy: string;
  }
) {
  await supabase.from("domain_events").insert({
    restaurant_id: params.restaurantId,
    event_type: params.eventType,
    payload: params.payload,
    published_by: params.publishedBy,
  });
}
