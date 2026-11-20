<script lang="ts">
  import type { InteractionAnswer, InteractionView, QuestionView } from './generated/workspace';

  let { interaction, disabled, respond }: {
    interaction: InteractionView;
    disabled: boolean;
    respond: (response: InteractionAnswer) => void;
  } = $props();

  let selectedOptions = $state<Record<string, string[]>>({});
  let textAnswers = $state<Record<string, string>>({});
  let permissions = $state<string[]>([]);

  function questionValues(question: QuestionView) {
    const text = textAnswers[question.id];
    const chosen = selectedOptions[question.id] ?? [];
    return [
      ...question.options.filter((option) => chosen.includes(option)),
      ...(question.acceptsText && text?.trim() ? [text] : []),
    ];
  }

  function toggleOption(question: string, option: string, checked: boolean) {
    const values = selectedOptions[question] ?? [];
    selectedOptions[question] = checked ? [...values, option] : values.filter((value) => value !== option);
  }
</script>

<section class="interaction-card">
  {#if 'approval' in interaction.content}
    {@const approval = interaction.content.approval}
    <p class="interaction-request">{approval.request}</p>
    <div class="interaction-actions">
      {#each approval.choices as choice (choice.index)}
        <button type="button" {disabled} onclick={() => respond({ decision: choice.index })}>{choice.label}</button>
      {/each}
    </div>
  {:else if 'permissions' in interaction.content}
    {@const request = interaction.content.permissions}
    {#if request.request}<p>{request.request}</p>{/if}
    <fieldset {disabled}>
      <legend>Permissions</legend>
      {#each request.permissions as permission (permission.key)}
        <label class="interaction-option">
          <input type="checkbox" value={permission.key} bind:group={permissions} />
          <span>{permission.label}{#if permission.detail}<pre>{permission.detail}</pre>{/if}</span>
        </label>
      {/each}
    </fieldset>
    <div class="interaction-actions">
      <button type="button" disabled={disabled || !permissions.length}
        onclick={() => respond({ permissions: { keys: [...permissions], forSession: false } })}>Allow for Turn</button>
      <button type="button" disabled={disabled || !permissions.length}
        onclick={() => respond({ permissions: { keys: [...permissions], forSession: true } })}>Allow for Session</button>
      <button type="button" {disabled}
        onclick={() => respond({ permissions: { keys: [], forSession: false } })}>Decline</button>
    </div>
  {:else}
    {@const questions = interaction.content.questions}
    {#each questions as question (question.id)}
      <fieldset {disabled}>
        <legend>{question.prompt}</legend>
        {#each question.options as option}
          <label class="interaction-option">
            <input type="checkbox" checked={selectedOptions[question.id]?.includes(option) ?? false}
              onchange={(event) => toggleOption(question.id, option, event.currentTarget.checked)} />
            <span>{option}</span>
          </label>
        {/each}
        {#if question.acceptsText}
          <input class="interaction-answer" type={question.secret ? 'password' : 'text'} aria-label={question.prompt}
            bind:value={textAnswers[question.id]} />
        {/if}
      </fieldset>
    {/each}
    <button type="button" disabled={disabled || questions.some((question) => !questionValues(question).length)}
      onclick={() => respond({ answers: questions.map((question) => ({ id: question.id, values: questionValues(question) })) })}>
      Submit Answers
    </button>
  {/if}
</section>
