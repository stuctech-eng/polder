import type { Permission } from "@/lib/user-management/role-helpers";

export interface ManualSection {
  id: string;
  title: string;
  relevantFor: Permission[]; // gebruikt alleen om volgorde te bepalen, niet toegang
  summary: string;
  steps: { title: string; detail: string }[];
}

export const MANUAL_SECTIONS: ManualSection[] = [
  {
    id: "aan-de-slag",
    title: "Aan de slag",
    relevantFor: [], // voor iedereen even relevant, altijd bovenaan als "algemeen"
    summary: "Inloggen en wachtwoord vergeten.",
    steps: [
      {
        title: "Inloggen",
        detail:
          "Ga naar de link van Polder, vul je e-mailadres en wachtwoord in. Ontvang je deze niet zelf gekozen, vraag de eigenaar om een uitnodiging.",
      },
      {
        title: "Wachtwoord vergeten",
        detail:
          "Tik op 'Wachtwoord vergeten?' op het inlogscherm, vul je e-mailadres in, en volg de link in de mail. Komt er geen mail? Vraag de eigenaar om je wachtwoord handmatig te resetten.",
      },
    ],
  },
  {
    id: "rekeningen-bonnen",
    title: "Rekeningen & bonnen",
    relevantFor: ["MANAGE_OPEN_TABS", "MANAGE_RECEIPTS"],
    summary: "Een zakelijke rekening openen, bonnen toevoegen, en afsluiten.",
    steps: [
      {
        title: "Nieuwe rekening openen",
        detail:
          "Ga naar 'Rekeningen' → '+ Nieuwe rekening'. Kies het bedrijf (en eventueel afdeling/kostenplaats/project), vul tafel en aantal personen in.",
      },
      {
        title: "Bon toevoegen",
        detail:
          "Open de rekening → '+ Bon toevoegen'. Vul per product: omschrijving, aantal, prijs per stuk (excl. BTW), en BTW-tarief. Prijzen mag je met komma of punt intikken.",
      },
      {
        title: "Rekening sluiten",
        detail:
          "Als de gast klaar is en er komen geen bonnen meer bij: tik 'Rekening sluiten'. Let op — hierna kunnen geen nieuwe bonnen meer toegevoegd worden, wel nog bestaande bonnen bewerkt (tot aan facturatie).",
      },
      {
        title: "Bon bewerken/verwijderen",
        detail:
          "Kan zolang de bon niet vergrendeld (goedgekeurd) of de rekening nog niet gefactureerd is. Daarna is een bon onveranderlijk voor de boekhoudkundige juistheid.",
      },
    ],
  },
  {
    id: "goedkeuring",
    title: "Goedkeuring van bonnen",
    relevantFor: ["APPROVE_RECEIPTS"],
    summary: "Hoe PIN- of bevestigings-goedkeuring werkt, als een bedrijf dat vereist.",
    steps: [
      {
        title: "Wanneer verschijnt dit?",
        detail:
          "Alleen als voor het gekoppelde bedrijf 'Goedkeuring bij bonnen' is ingeschakeld (in te stellen op de bedrijfspagina). De bon toont dan 'wacht op goedkeuring'.",
      },
      {
        title: "PIN-methode",
        detail:
          "Vul de PIN-code in bij de bon en tik 'Goedkeuren'. De PIN is een interne code voor personeel (manager/eigenaar), nooit voor de klant zelf.",
      },
      {
        title: "Restaurant bevestigt",
        detail:
          "Geen code nodig — een geautoriseerde gebruiker klikt gewoon op 'Goedkeuren'. De vergrendeling gebeurt automatisch daarna.",
      },
      {
        title: "E-mail (voor wie niet inlogt)",
        detail:
          "Een unieke link wordt gemaild naar het ingestelde adres — handig voor een manager op afstand. Geen account nodig, gewoon de link openen en op 'Goedkeuren' tikken.",
      },
      {
        title: "QR-code (voor wie niet inlogt)",
        detail:
          "Zelfde unieke link als E-mail, maar als scanbare code getoond bij de bon. Handig als er geen mailadres beschikbaar is, of voor een snelle scan ter plekke.",
      },
      {
        title: "Na goedkeuring",
        detail:
          "De bon wordt vergrendeld ('locked') en kan niet meer gewijzigd of verwijderd worden.",
      },
    ],
  },
  {
    id: "bedrijven",
    title: "Bedrijven beheren",
    relevantFor: ["MANAGE_COMPANIES", "MANAGE_SETTINGS"],
    summary: "Bedrijf aanmaken, afdelingen/kostenplaatsen/projecten, en instellingen.",
    steps: [
      {
        title: "Nieuw bedrijf",
        detail: "Ga naar 'Bedrijven' → '+ Nieuw bedrijf'. Vul naam, adres, BTW/KvK-nummer en factuur-e-mail in.",
      },
      {
        title: "Afdelingen / Kostenplaatsen / Projecten",
        detail:
          "Optioneel, alleen invullen als het bedrijf dat nodig heeft. Worden aangeboden bij het openen van een rekening voor dat bedrijf.",
      },
      {
        title: "Bedrijfsreferenties (routecode/WBS/budgetcode)",
        detail:
          "Interne referentiecodes van de klant zelf, per type toe te voegen op de bedrijfspagina.",
      },
      {
        title: "Facturatieregel",
        detail:
          "Bepaal hoe vaak dit bedrijf gefactureerd wordt (direct/wekelijks/maandelijks/per project) en of goedkeuring vereist is.",
      },
      {
        title: "Goedkeuring bij bonnen instellen",
        detail: "Zet aan/uit, kies methode (PIN of Restaurant bevestigt), stel een PIN in indien gekozen.",
      },
      {
        title: "Bedrijf deactiveren",
        detail:
          "Bedrijven worden nooit hard verwijderd (historische facturen moeten intact blijven) — alleen gedeactiveerd, zodat ze niet meer gekozen kunnen worden bij nieuwe rekeningen.",
      },
    ],
  },
  {
    id: "facturatie",
    title: "Facturatie",
    relevantFor: ["MANAGE_INVOICES"],
    summary: "Factuur genereren vanuit een gesloten rekening, en downloaden.",
    steps: [
      {
        title: "Factuur genereren",
        detail:
          "Open een gesloten rekening → 'Factuur genereren'. Dit bundelt alle gekoppelde bonnen, berekent het totaal, en maakt een PDF. Kan niet als er nog een bon op goedkeuring wacht.",
      },
      {
        title: "Factuur downloaden",
        detail: "Via de rekening zelf, of het overzicht onder 'Facturen'. De link is tijdelijk (5 minuten geldig) om de PDF te beschermen.",
      },
      {
        title: "Factuur mailen naar de klant",
        detail:
          "Nog niet actief — wacht op een geverifieerd eigen domein bij Resend (beslissing bij de eigenaar).",
      },
    ],
  },
  {
    id: "dagafsluiting",
    title: "Dagafsluiting",
    relevantFor: ["VIEW_DAILY_CLOSING", "EXECUTE_DAILY_CLOSING"],
    summary: "Operationele controle vóór het afsluiten van de kassa — anders dan het Dashboard.",
    steps: [
      {
        title: "Wat is het verschil met het Dashboard?",
        detail:
          "Dashboard = managementinformatie (maandomzet, trends). Dagafsluiting = dagelijkse controle: klopt alles vóór je de kassa dichtdoet?",
      },
      {
        title: "Controles bekijken",
        detail:
          "Open/gesloten rekeningen, bonnen wachtend op goedkeuring, conceptbonnen. Sommige controles tonen '—' (n.v.t.) omdat die functionaliteit nog niet gebouwd is — dat is geen fout.",
      },
      {
        title: "Dag afsluiten",
        detail:
          "Alleen eigenaar/manager kunnen dit. Bij openstaande waarschuwingen vraagt het systeem een extra bevestiging. Een dag kan maar één keer afgesloten worden.",
      },
    ],
  },
  {
    id: "team",
    title: "Team beheren",
    relevantFor: ["MANAGE_TEAM"],
    summary: "Medewerkers uitnodigen, rollen toewijzen, activeren/deactiveren.",
    steps: [
      {
        title: "Medewerker uitnodigen",
        detail:
          "Ga naar 'Team' → '+ Uitnodigen'. Vul naam, e-mailadres en rol in. De medewerker ontvangt een mail om zelf een wachtwoord te kiezen (let op de Resend-testlimiet, zie Facturatie-sectie).",
      },
      {
        title: "Rol wijzigen",
        detail: "Kies een andere rol in de dropdown naast het teamlid. De laatste eigenaar kan niet gedegradeerd worden.",
      },
      {
        title: "Activeren/deactiveren",
        detail:
          "Een gedeactiveerd account kan niet meer inloggen. Je kan jezelf niet deactiveren, en de laatste actieve eigenaar is altijd beschermd.",
      },
      {
        title: "Verwijderen",
        detail:
          "Alleen mogelijk als de gebruiker geen historie heeft (geen bonnen/facturen/activiteit) — anders geeft het systeem een duidelijke melding om te deactiveren i.p.v. te verwijderen.",
      },
    ],
  },
];
