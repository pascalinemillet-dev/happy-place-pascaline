import { useState } from "react";
import { ErrorSummary, Field, FormActions, Modal, TextArea } from "@/components/manage/crud-ui";
import { CharCounter } from "@/components/expandable-card";
import { rejectionSchema, validate, type FieldErrors } from "@/lib/manage-schemas";
import { REJECTION_CATEGORIES, type RejectionCategory, type Submission } from "@/lib/dashboard";

/** Fenêtre « Refuser la soumission » : motif obligatoire (dont « doublon ») et raison obligatoire. */
export function RejectModal({
  submission,
  pending,
  onCancel,
  onConfirm,
}: {
  submission: Submission;
  pending: boolean;
  onCancel: () => void;
  onConfirm: (values: { rejection_category: RejectionCategory; rejection_note: string }) => void;
}) {
  const [form, setForm] = useState({ rejection_category: "", rejection_note: "" });
  const [errors, setErrors] = useState<FieldErrors>({});

  return (
    <Modal title="Refuser la soumission" onClose={onCancel}>
      <form
        noValidate
        className="space-y-sm"
        onSubmit={(e) => {
          e.preventDefault();
          const res = validate(rejectionSchema, form);
          if (!res.ok) return setErrors(res.errors);
          setErrors({});
          onConfirm(res.data);
        }}
      >
        <p className="max-h-48 overflow-y-auto border border-outline-variant bg-surface-container-low p-xs text-body-sm italic text-on-surface-variant whitespace-pre-line wrap-anywhere">
          “{submission.content}”
        </p>
        <ErrorSummary errors={errors} />
        <Field label="Motif du refus" error={errors.rejection_category}>
          <select
            className="w-full border border-outline-variant bg-card p-xs text-body-sm"
            value={form.rejection_category}
            onChange={(e) => setForm({ ...form, rejection_category: e.target.value })}
          >
            <option value="">— Choisir un motif —</option>
            {REJECTION_CATEGORIES.map((c) => (
              <option key={c} value={c}>
                {c}
              </option>
            ))}
          </select>
        </Field>
        <Field label="Raison du refus (obligatoire)" error={errors.rejection_note}>
          <TextArea
            rows={4}
            value={form.rejection_note}
            placeholder="Explique à l'auteur pourquoi sa soumission est refusée…"
            onChange={(e) => setForm({ ...form, rejection_note: e.target.value })}
          />
          <CharCounter value={form.rejection_note} max={500} />
        </Field>
        <FormActions pending={pending} onCancel={onCancel} />
      </form>
    </Modal>
  );
}
