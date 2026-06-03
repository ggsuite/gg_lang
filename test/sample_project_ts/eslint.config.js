// Minimal flat ESLint config for the TypeScript fixture.
export default [
  {
    files: ['src/**/*.ts', 'test/**/*.ts'],
    rules: {
      'no-unused-vars': 'error',
      'no-undef': 'error',
    },
  },
];
