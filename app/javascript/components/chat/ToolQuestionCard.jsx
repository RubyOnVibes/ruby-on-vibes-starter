import React, { useEffect, useId, useState } from 'react'

function initialValue(field) {
  if (field.default == null) return field.type === 'array' && field.choices?.length ? [] : ''
  if (field.type === 'array') {
    return field.choices?.length ? field.default.map(String) : field.default.join('\n')
  }
  return String(field.default)
}

function fieldAnswer(field, value) {
  if (field.type === 'array') {
    if (field.choices?.length) return field.choices.filter((choice) => value.includes(String(choice)))
    return value.split('\n').map((line) => line.trim()).filter(Boolean)
  }
  if (field.choices?.length) return field.choices.find((choice) => String(choice) === value)
  if (field.type === 'boolean') return value === 'true'
  if (field.type === 'number' || field.type === 'integer') return Number(value)
  return value
}

function choiceLabel(field, choice) {
  const label = field.choice_titles?.[String(choice)] ?? choice
  return typeof label === 'boolean' ? (label ? 'Yes' : 'No') : String(label)
}

function safeQuestionUrl(value) {
  try {
    const url = new URL(value)
    return ['https:', 'http:'].includes(url.protocol) ? url.href : null
  } catch {
    return null
  }
}

export default function ToolQuestionCard({ question, chatRunId }) {
  const inputPrefix = useId()
  const fields = question.fields || []
  const [values, setValues] = useState(() => Object.fromEntries(fields.map((field) => [field.name, initialValue(field)])))
  const [textAnswer, setTextAnswer] = useState('')
  const [status, setStatus] = useState(question.status || 'pending')
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState(null)

  useEffect(() => {
    setStatus(question.status || 'pending')
  }, [question.id, question.status])

  const pending = status === 'pending'
  const isUrl = question.kind === 'url'
  const url = isUrl ? safeQuestionUrl(question.url) : null
  const disabled = submitting || !chatRunId
  const inputClass = 'w-full rounded-md border border-input bg-background px-3 py-2 text-sm text-foreground focus:outline-none focus:ring-2 focus:ring-ring disabled:opacity-50'

  const respond = async (action) => {
    if (!pending || disabled) return

    setSubmitting(true)
    setError(null)

    const payload = { question_id: question.id }
    if (action === 'answer') {
      payload.answer = isUrl ? null : fields.length ? Object.fromEntries(
        fields.filter((field) => values[field.name] !== '' && values[field.name] != null)
          .map((field) => [field.name, fieldAnswer(field, values[field.name])])
      ) : textAnswer
    }

    try {
      const response = await fetch(`/chat_runs/${encodeURIComponent(chatRunId)}/questions/${action}`, {
        method: 'POST',
        headers: {
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content || '',
          'Accept': 'application/json',
          'Content-Type': 'application/json'
        },
        body: JSON.stringify(payload)
      })
      const body = await response.json().catch(() => ({}))
      if (!response.ok) {
        if (response.status === 404 || response.status === 409) setStatus('unavailable')
        throw new Error(body.error || 'Could not submit your response. Please try again.')
      }
      setStatus(body.status || (action === 'answer' ? 'answered' : 'declined'))
    } catch (err) {
      setError(err.message)
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <section className="not-prose my-3 rounded-lg border border-border bg-surface-1 p-3 text-sm text-foreground" aria-label="Assistant question">
      <div className="flex items-start justify-between gap-3">
        <p className="m-0 whitespace-pre-wrap font-semibold">{question.message || 'Your response is needed'}</p>
        {!pending && (
          <span className="shrink-0 rounded-full bg-surface-2 px-2 py-1 text-xs text-muted-foreground" role="status">
            {status === 'answered' ? 'Answered' : status === 'declined' ? 'Declined' : 'No longer pending'}
          </span>
        )}
      </div>

      {isUrl && (
        <div className="mt-3 break-all">
          {url ? (
            <a href={url} target="_blank" rel="noopener noreferrer" className="text-primary underline">
              {question.url}
              <span className="sr-only"> (opens in a new tab)</span>
            </a>
          ) : <p className="text-destructive">This request did not include a valid web address.</p>}
        </div>
      )}

      {pending && (
        <form className="mt-3 space-y-3" onSubmit={(event) => { event.preventDefault(); respond('answer') }}>
          {!isUrl && fields.map((field, index) => {
            const inputId = `${inputPrefix}-${index}`
            const descriptionId = `${inputId}-description`
            const value = values[field.name] ?? ''
            const update = (nextValue) => setValues((previous) => ({ ...previous, [field.name]: nextValue }))
            const options = field.choices?.length ? field.choices : field.type === 'boolean' ? [true, false] : null
            const multiple = field.type === 'array' && Boolean(options)
            const inputProps = {
              id: inputId,
              name: field.name,
              required: field.required,
              disabled,
              'aria-describedby': field.description ? descriptionId : undefined,
              className: inputClass
            }

            return (
              <div key={field.name}>
                <label htmlFor={inputId} className="mb-1 block font-medium">
                  {field.title || field.name}{field.required ? ' (required)' : ''}
                </label>
                {field.description && <p id={descriptionId} className="mb-2 text-xs text-muted-foreground">{field.description}</p>}
                {options ? (
                  <select
                    {...inputProps}
                    multiple={multiple}
                    value={value}
                    onChange={(event) => update(multiple ? Array.from(event.target.selectedOptions, (option) => option.value) : event.target.value)}
                  >
                    {!multiple && <option value="">Choose an answer</option>}
                    {options.map((choice) => (
                      <option key={String(choice)} value={String(choice)}>
                        {choiceLabel(field, choice)}
                      </option>
                    ))}
                  </select>
                ) : field.type === 'number' || field.type === 'integer' ? (
                  <input {...inputProps} type="number" step={field.type === 'integer' ? '1' : 'any'} value={value} onChange={(event) => update(event.target.value)} />
                ) : (
                  <textarea {...inputProps} rows={field.type === 'array' ? 3 : 2} value={value} onChange={(event) => update(event.target.value)} />
                )}
                {field.type === 'array' && <p className="mt-1 text-xs text-muted-foreground">{options ? 'You can select multiple answers.' : 'Enter one item per line.'}</p>}
              </div>
            )
          })}

          {!isUrl && fields.length === 0 && (
            <div>
              <label htmlFor={`${inputPrefix}-answer`} className="mb-1 block font-medium">Your answer</label>
              <textarea id={`${inputPrefix}-answer`} required disabled={disabled} className={inputClass} rows={3} value={textAnswer} onChange={(event) => setTextAnswer(event.target.value)} />
            </div>
          )}

          <div className="flex flex-wrap gap-2">
            <button type="submit" disabled={disabled || (isUrl && !url)} className="btn btn-primary disabled:opacity-50">
              {submitting ? 'Submitting…' : isUrl ? 'I’ve completed this' : 'Submit answer'}
            </button>
            <button type="button" disabled={disabled} onClick={() => respond('decline')} className="btn btn-secondary disabled:opacity-50">Decline</button>
          </div>
        </form>
      )}

      {error && <p className="mt-2 text-xs text-destructive" role="alert">{error}</p>}
    </section>
  )
}
