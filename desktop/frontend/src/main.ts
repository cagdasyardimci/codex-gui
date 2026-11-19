import { mount } from 'svelte';
import DiagnosticShell from './DiagnosticShell.svelte';

const target = document.getElementById('app');
if (!target) {
  throw new Error('Missing application mount point');
}

mount(DiagnosticShell, { target });
