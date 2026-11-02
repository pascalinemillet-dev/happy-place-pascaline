import { useEffect, useRef, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  ErrorSummary,
  Field,
  FormActions,
  Modal,
  Select,
  TextArea,
} from "@/components/manage/crud-ui";
import { CharCounter, rejectionErrorMessage } from "@/components/expandable-card";
import { newSubmissionSchema, validate, type FieldErrors } from "@/lib/manage-schemas";
import {
  SEVERITY_LABELS,
  submitSubmission,
  type BlockerSeverity,
  type SubmissionKind,
} from "@/lib/dashboard";
import {
  ADMIN_LABEL,
  assigneeHint,
  assigneeLine,
  fetchAssigneeNames,
  fetchMyProfile,
  trackEvent,
} from "@/lib/f1";
import { toast } from "sonner";

const KIND_CHOICES: { kind: SubmissionKind; title: string; help: string }[] = [
  { kind: "idée", title: "Idée", help: "Une idée, une demande ou une question" },
  { kind: "point bloquant", title: "Point bloquant", help: "Un problème qui freine le travail" },
];

export type SentSubmission = { kind: SubmissionKind; assignedTo: string };

/** Formulaire « Soumettre » : type, personne assignée, description, sévérité (US29, US30). */
export function SubmitModal({
  role,
  email,
  managerTeams,
  onClose,
  onSent,
}: {
  role: string;
  email: string;
  managerTeams: string[];
  onClose: () => void;
  onSent: (sent: SentSubmission) => void;
}) {
  const qc = useQueryClient();
  const openedAt = useRef(Date.now());
  const [kind, setKind] = useState<SubmissionKind | null>(null);
  const [severity, setSeverity] = useState<BlockerSeverity | "">("");
  const [content, setContent] = useState("");
  const [team, setTeam] = useState(managerTeams.length === 1 ? managerTeams[0] : "");
  const [attachment, setAttachment] = useState<File | null>(null);
  const [errors, setErrors] = useState<FieldErrors>({});

  const profile = useQuery({
    queryKey: ["profile", email],
    queryFn: () => fetchMyProfile(email),
    retry: false,
  });
  useEffect(() => {
    if (!team && managerTeams.length === 1) setTeam(managerTeams[0]);
  }, [managerTeams, team]);

  const ownTeam =
    role === "admin" ? "Admin" : role === "manager" ? team : (profile.data?.team ?? "");
  const assignees = useQuery({
    queryKey: ["assignees", role, ownTeam],
    queryFn: () => fetchAssigneeNames(ownTeam || null),
    enabled: !!kind && (role !== "manager" || !!team),
    retry: false,
  });
  const managers = assignees.data ?? [];
  const assigned = kind ? assigneeLine(kind, managers) : "";

  const submit = useMutation({
    mutationFn: (input: Parameters<typeof submitSubmission>[0]) =>
      submitSubmission(input, attachment),
    onSuccess: (_d, input) => {
      trackEvent("submission_sent", "soumettre", {
        kind: input.kind,
        seconds: Math.round((Date.now() - openedAt.current) / 1000),
      });
      qc.invalidateQueries({ queryKey: ["submissions"] });
      onSent({ kind: input.kind, assignedTo: assigned });
    },
    onError: (e: unknown) => toast.error(rejectionErrorMessage(e)),
  });

  function choose(next: SubmissionKind) {
    setKind(next);
    setErrors((e) => {
      const { kind: _k, ...rest } = e;
      return rest;
    });
    trackEvent("submission_type_selected", "soumettre", { kind: next });
  }

  function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    const result = validate(newSubmissionSchema, {
      kind,
      severity: kind === "point bloquant" && severity ? severity : null,
      author_name: profile.data?.fullName ?? "",
      team:
        role === "collaborateur" ? (profile.data?.team ?? "") : role === "admin" ? "Admin" : team,
      content,
    });
    if (!result.ok) {
      setErrors(result.errors);
      return;
    }
    setErrors({});
    submit.mutate(result.data);
  }

  const teamLabel = role === "admin" ? "Administration HappyPlace" : ownTeam || "équipe à choisir";

  return (
    <Modal title="Soumettre" onClose={onClose}>
      <form onSubmit={onSubmit} className="space-y-md" noValidate>
        <ErrorSummary errors={errors} />

        <div className="bg-surface-container-low p-sm space-y-1">
          <p className="font-label-sm text-label-sm text-on-surface-variant uppercase">Auteur</p>
          <p className="font-body-md text-primary font-bold">
            {profile.data?.fullName ?? "…"} · {teamLabel}
          </p>
          <p className="text-body-sm text-on-surface-variant">Repris de votre compte.</p>
        </div>

        {role === "manager" && managerTeams.length > 1 && (
          <Field label="Équipe concernée *" error={errors.team}>
            <Select value={team} onChange={(e) => setTeam(e.target.value)}>
              <option value="">Choisis une de tes équipes</option>
              {managerTeams.map((t) => (
                <option key={t} value={t}>
                  {t}
                </option>
              ))}
            </Select>
          </Field>
        )}

        <fieldset className="space-y-xs">
          <legend className="font-label-sm text-label-sm text-on-surface-variant uppercase">
            Type de soumission *
          </legend>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-sm">
            {KIND_CHOICES.map((c) => {
              const selected = kind === c.kind;
              return (
                <label
                  key={c.kind}
                  className={`flex cursor-pointer items-start gap-sm border p-sm focus-within:ring-2 focus-within:ring-primary ${
                    selected
                      ? "border-2 border-primary bg-card"
                      : "border-outline-variant bg-card hover:bg-surface-container"
                  }`}
                >
                  <input
                    type="radio"
                    name="submission-kind"
                    value={c.kind}
                    checked={selected}
                    onChange={() => choose(c.kind)}
                    className="sr-only"
                  />
                  <span
                    aria-hidden="true"
                    className={`mt-1 inline-block h-4 w-4 shrink-0 rounded-full border ${
                      selected
                        ? "border-primary bg-primary ring-2 ring-inset ring-card"
                        : "border-outline"
                    }`}
                  />
                  <span className="min-w-0">
                    <span className="block font-body-md text-primary font-bold">{c.title}</span>
                    <span className="block text-body-sm text-on-surface-variant">{c.help}</span>
                  </span>
                </label>
              );
            })}
          </div>
          {errors.kind && (
            <p role="alert" className="text-body-sm text-error">
              {errors.kind}
            </p>
          )}
        </fieldset>

        {kind && (
          <div className="space-y-1" aria-live="polite">
            <p className="font-label-sm text-label-sm text-on-surface-variant uppercase">
              Assigné à
            </p>
            {role === "manager" && !team ? (
              <p className="text-body-sm text-on-surface-variant">
                Choisis d'abord l'équipe concernée.
              </p>
            ) : assignees.isLoading ? (
              <p className="text-body-sm text-on-surface-variant">Chargement…</p>
            ) : (
              <>
                <p className="font-body-md text-primary">{assigned || ADMIN_LABEL}</p>
                <p className="text-body-sm text-on-surface-variant">
                  {role === "admin"
                    ? "L'administration examinera votre soumission."
                    : assigneeHint(kind, managers)}
                </p>
              </>
            )}
          </div>
        )}

        <Field label="Description *" error={errors.content}>
          <TextArea
            rows={5}
            value={content}
            aria-label="Description"
            aria-describedby="soumettre-description-aide"
            placeholder={
              kind === "point bloquant"
                ? "Décris ce qui bloque ton travail et depuis quand…"
                : "Décris ton idée, ta demande ou ta question…"
            }
            onChange={(e) => setContent(e.target.value)}
          />
          <CharCounter value={content} max={2000} min={5} />
          {/* Aide de la décision du 2026-11-01 : minimiser les noms envoyés à l'IA (US29, R8). */}
          <p id="soumettre-description-aide" className="text-body-sm text-on-surface-variant">
            Décris la situation sans nommer de collègue ni de candidat : indique plutôt son rôle ou
            son équipe. Ce texte peut être résumé par une IA.
          </p>
        </Field>

        {kind === "point bloquant" && (
          <Field label="Sévérité *" error={errors.severity}>
            <Select
              value={severity}
              onChange={(e) => setSeverity(e.target.value as BlockerSeverity | "")}
            >
              <option value="">Choisis une sévérité</option>
              {(Object.keys(SEVERITY_LABELS) as BlockerSeverity[]).map((s) => (
                <option key={s} value={s}>
                  {SEVERITY_LABELS[s]}
                </option>
              ))}
            </Select>
            <p className="text-body-sm text-on-surface-variant">
              Votre manager ou l'administration pourra l'ajuster.
            </p>
          </Field>
        )}

        <Field label="Document PDF (optionnel, 20 Mo max)" error={errors.attachment}>
          <input
            type="file"
            accept="application/pdf,.pdf"
            className="block w-full text-body-sm"
            onChange={(e) => {
              const f = e.target.files?.[0] ?? null;
              const fail = (message: string) => {
                setErrors((prev) => ({ ...prev, attachment: message }));
                e.target.value = "";
                setAttachment(null);
              };
              if (f && f.type !== "application/pdf")
                return fail("Seuls les fichiers PDF sont acceptés.");
              if (f && f.size > 20 * 1024 * 1024) return fail("Le fichier dépasse 20 Mo.");
              setErrors((prev) => {
                const { attachment: _a, ...rest } = prev;
                return rest;
              });
              setAttachment(f);
            }}
          />
        </Field>

        <FormActions pending={submit.isPending} submitLabel="ENVOYER" onCancel={onClose} />
      </form>
    </Modal>
  );
}
