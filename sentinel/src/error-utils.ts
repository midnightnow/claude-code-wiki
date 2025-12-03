/**
 * =============================================================================
 * ERROR UTILITIES
 * =============================================================================
 *
 * Functions for canonicalizing error messages into searchable signatures.
 * This enables cross-session and cross-project pattern matching.
 */

/**
 * Patterns to strip from error messages for canonicalization
 */
const STRIP_PATTERNS: RegExp[] = [
  // File paths (absolute and relative)
  /(?:[a-zA-Z]:)?(?:[\\/][\w.-]+)+[\\/]([\w.-]+)/g,
  // Line and column numbers (:123:45)
  /:\d+:\d+/g,
  // Memory addresses (0x123abc)
  /0x[a-fA-F0-9]{6,}/g,
  // UUIDs
  /[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}/gi,
  // Large numbers (timestamps, IDs)
  /\b\d{6,}\b/g,
  // Hex strings (hashes, tokens)
  /\b[a-fA-F0-9]{16,}\b/g,
  // Quoted strings (often variable content)
  /"[^"]{20,}"/g,
  /'[^']{20,}'/g,
];

/**
 * Error type prefixes to preserve (the "what" of the error)
 */
const ERROR_TYPE_PATTERNS: RegExp[] = [
  /^(TypeError):/,
  /^(ReferenceError):/,
  /^(SyntaxError):/,
  /^(RangeError):/,
  /^(Error):/,
  /^(AssertionError):/,
  /^(ValidationError):/,
  /^(NetworkError):/,
  /^(TimeoutError):/,
  /^(PermissionError):/,
  /^(AuthenticationError):/,
  /^(NotFoundError):/,
  /^(\w+Error):/,
];

/**
 * Generates a canonical signature from a raw error message.
 *
 * This signature is used to identify recurring errors across sessions
 * and projects, even when specific details (paths, IDs) change.
 *
 * @example
 * Input:  "TypeError: Cannot read property 'email' of undefined at /Users/dev/project/src/auth.ts:123:45"
 * Output: "TypeError: Cannot read property 'email' of undefined"
 *
 * @param rawError - The full error message, possibly including stack trace
 * @returns A canonical signature string
 */
export function generateErrorSignature(rawError: string): string {
  if (!rawError || typeof rawError !== 'string') {
    return 'generic:invalid_error_input';
  }

  // Take only the first line (the error message, not the stack)
  let signature = rawError.split('\n')[0].trim();

  // Preserve the error type if present
  let errorType = '';
  for (const pattern of ERROR_TYPE_PATTERNS) {
    const match = signature.match(pattern);
    if (match) {
      errorType = match[1] + ': ';
      break;
    }
  }

  // Strip variable content
  for (const pattern of STRIP_PATTERNS) {
    signature = signature.replace(pattern, ' ');
  }

  // Clean up whitespace
  signature = signature
    .replace(/\s+/g, ' ')
    .trim()
    .substring(0, 200); // Limit length

  // Ensure we have something meaningful
  if (signature.length < 5) {
    return 'generic:short_error';
  }

  return signature;
}

/**
 * Extracts the error type from an error message
 *
 * @example
 * Input:  "TypeError: Cannot read property 'x' of null"
 * Output: "TypeError"
 */
export function extractErrorType(rawError: string): string {
  if (!rawError || typeof rawError !== 'string') {
    return 'UnknownError';
  }

  const firstLine = rawError.split('\n')[0];

  for (const pattern of ERROR_TYPE_PATTERNS) {
    const match = firstLine.match(pattern);
    if (match) {
      return match[1];
    }
  }

  return 'UnknownError';
}

/**
 * Calculates similarity between two error signatures
 *
 * @returns A score from 0 to 1, where 1 is identical
 */
export function calculateSignatureSimilarity(sig1: string, sig2: string): number {
  if (sig1 === sig2) return 1;
  if (!sig1 || !sig2) return 0;

  // Tokenize both signatures
  const tokens1 = new Set(sig1.toLowerCase().split(/\s+/));
  const tokens2 = new Set(sig2.toLowerCase().split(/\s+/));

  // Calculate Jaccard similarity
  const intersection = new Set([...tokens1].filter(t => tokens2.has(t)));
  const union = new Set([...tokens1, ...tokens2]);

  return intersection.size / union.size;
}

/**
 * Parses test failure output into structured error information
 */
export interface ParsedTestError {
  testName: string;
  testFile?: string;
  errorType: string;
  errorMessage: string;
  signature: string;
  stackTrace?: string;
}

export function parseTestError(
  testName: string,
  errorOutput: string,
  testFile?: string
): ParsedTestError {
  const errorType = extractErrorType(errorOutput);
  const signature = generateErrorSignature(errorOutput);

  // Extract just the message (first line without type prefix)
  const firstLine = errorOutput.split('\n')[0];
  const messageMatch = firstLine.match(/^\w+Error:\s*(.+)$/);
  const errorMessage = messageMatch ? messageMatch[1] : firstLine;

  // Extract stack trace (everything after first line)
  const lines = errorOutput.split('\n');
  const stackTrace = lines.slice(1).join('\n').trim() || undefined;

  return {
    testName,
    testFile,
    errorType,
    errorMessage,
    signature,
    stackTrace,
  };
}

export default {
  generateErrorSignature,
  extractErrorType,
  calculateSignatureSimilarity,
  parseTestError,
};
