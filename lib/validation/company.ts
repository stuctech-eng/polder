import { z } from "zod";

export const companySchema = z.object({
  name: z.string().min(2, "Naam is verplicht (min. 2 tekens)"),
  address: z.string().optional(),
  vatNumber: z.string().optional(),
  cocNumber: z.string().optional(),
  invoiceEmail: z.string().email("Ongeldig e-mailadres").optional().or(z.literal("")),
  paymentTermDays: z.number().int().positive().default(30),
  notes: z.string().optional(),
});

export const companyUpdateSchema = companySchema.partial().extend({
  name: z.string().min(2, "Naam is verplicht (min. 2 tekens)"),
  isActive: z.boolean().optional(),
});

export type CompanyInput = z.infer<typeof companySchema>;
