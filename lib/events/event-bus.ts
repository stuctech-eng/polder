import type { SupabaseClient } from "@supabase/supabase-js";
import type { DomainEvent } from "./types";

type Handler = (event: DomainEvent) => Promise<void> | void;

/**
 * Interne Event Bus (Fase 1).
 *
 * Simpele in-memory pub/sub + persistente log in `domain_events`.
 * Bij schaal kan de transportlaag vervangen worden door een externe
 * message broker zonder dat modules die publish()/subscribe() aanroepen
 * hoeven te wijzigen (governance-principe 6.1).
 */
class EventBus {
  private handlers = new Map<string, Handler[]>();

  subscribe(eventType: DomainEvent["eventType"], handler: Handler) {
    const existing = this.handlers.get(eventType) ?? [];
    existing.push(handler);
    this.handlers.set(eventType, existing);
  }

  async publish(event: DomainEvent, supabase: SupabaseClient) {
    // Database is de bron van waarheid (governance-principe 6.2):
    // eerst persisteren, dan pas handlers uitvoeren.
    const { error } = await supabase.from("domain_events").insert({
      restaurant_id: event.restaurantId,
      event_type: event.eventType,
      payload: event.payload,
      published_by: event.publishedBy ?? null,
    });

    if (error) {
      // Publiceren mag falen zonder de aanroepende module te breken,
      // maar moet zichtbaar zijn (sectie 15: fouten zichtbaar in de app).
      console.error("[EventBus] Kon event niet persisteren:", error.message);
    }

    const handlers = this.handlers.get(event.eventType) ?? [];
    await Promise.all(handlers.map((handler) => handler(event)));
  }
}

export const eventBus = new EventBus();
