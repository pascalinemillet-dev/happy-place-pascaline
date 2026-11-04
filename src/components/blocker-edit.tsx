import { useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import {
  ConfirmDelete,
  ErrorSummary,
  Field,
  FormActions,
  Modal,
  Select,
  TextArea,
  TextInput,
} from "@/components/manage/crud-ui";
import { blockerSchema, validate, type FieldErrors } from "@/lib/manage-schemas";
import { deleteBlocker, updateBlocker, type Blocker, type BlockerInput } from "@/lib/dashboard";

/**
 * Modifier un point bloquant depuis le dashboard (2026-11-04) : l'admin pour tous,
 * le manager pour ceux de ses équipes. `teams` limite le pôle : toutes les équipes
 * pour l'admin, celles du manager pour le manager. La base applique la même règle (RLS).
 */
export function BlockerEditModal({
  blocker,
  teams,
  onClose,
}: {
  blocker: Blocker;
  teams: string[];
  onClose: () => void;
}) {
  const qc = useQueryClient();
  const [form, setForm] = useState<BlockerInput>({
    title: blocker.title,
    description: blocker.description ?? "",
    department: blocker.department,
    severity: blocker.severity,
    status: blocker.status,
  });
  const [errors, setErrors] = useState<FieldErrors>({});
  const choices = teams.includes(form.department) ? teams : [form.department, ...teams];

  const save = useMutation({
    mutationFn: (input: BlockerInput) => updateBlocker(blocker.id, input),
    onSuccess: () => {
      toast.success("Point bloquant modifié");
      qc.invalidateQueries({ queryKey: ["blockers"] });
      onClose();
    },
    onError: (e: unknown) => toast.error((e as Error).message),
  });

  function submit(e: React.FormEvent) {
    e.preventDefault();
    const res = validate(blockerSchema, form);
    if (!res.ok) {
      setErrors(res.errors);
      return;
    }
    setErrors({});
    save.mutate(res.data);
  }

  return (
    <Modal title="Modifier le point bloquant" onClose={onClose}>
      <form onSubmit={submit} className="space-y-sm" noValidate>
        <ErrorSummary errors={errors} />
        <Field label="Titre" error={errors.title}>
          <TextInput
            value={form.title}
            maxLength={160}
            onChange={(e) => setForm({ ...form, title: e.target.value })}
          />
        </Field>
        <Field label="Description" error={errors.description}>
          <TextArea
            rows={4}
            value={form.description}
            maxLength={2000}
            onChange={(e) => setForm({ ...form, description: e.target.value })}
          />
        </Field>
        <Field label="Pôle concerné" error={errors.department}>
          <Select
            value={form.department}
            onChange={(e) => setForm({ ...form, department: e.target.value })}
          >
            {choices.map((t) => (
              <option key={t} value={t}>
                {t}
              </option>
            ))}
          </Select>
        </Field>
        <Field label="Sévérité" error={errors.severity}>
          <Select
            value={form.severity}
            onChange={(e) => setForm({ ...form, severity: e.target.value })}
          >
            <option value="critical">Critique</option>
            <option value="warning">Avertissement</option>
            <option value="info">Information</option>
          </Select>
        </Field>
        <Field label="Statut" error={errors.status}>
          <Select value={form.status} onChange={(e) => setForm({ ...form, status: e.target.value })}>
            <option value="OUVERT">OUVERT</option>
            <option value="EN COURS">EN COURS</option>
            <option value="SURVEILLANCE">SURVEILLANCE</option>
            <option
              value="RÉSOLU"
              disabled={blocker.status === "OUVERT"}
              title={blocker.status === "OUVERT" ? "Passe d'abord par EN COURS" : undefined}
            >
              RÉSOLU
            </option>
          </Select>
        </Field>
        <FormActions pending={save.isPending} onCancel={onClose} />
      </form>
    </Modal>
  );
}

/** Supprimer un point bloquant depuis le dashboard, après confirmation (2026-11-04). */
export function BlockerDeleteConfirm({
  blocker,
  onClose,
}: {
  blocker: Blocker;
  onClose: () => void;
}) {
  const qc = useQueryClient();
  const remove = useMutation({
    mutationFn: () => deleteBlocker(blocker.id),
    onSuccess: () => {
      toast.success("Point bloquant supprimé");
      qc.invalidateQueries({ queryKey: ["blockers"] });
      qc.invalidateQueries({ queryKey: ["submissions"] });
      onClose();
    },
    onError: (e: unknown) => toast.error((e as Error).message),
  });
  return (
    <ConfirmDelete
      label={blocker.title}
      pending={remove.isPending}
      onCancel={onClose}
      onConfirm={() => remove.mutate()}
    />
  );
}
