# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 0.1.x   | :white_check_mark: |
| < 0.1   | :x:                |

## Reporting a Vulnerability

We take security seriously. If you discover a security vulnerability, please report it responsibly.

### Private Vulnerability Reporting

**Preferred method**: Use GitHub's private vulnerability reporting feature:
1. Go to the [Security tab](https://github.com/danieljustus/symaira-terminal/security)
2. Click "Report a vulnerability"
3. Fill in the details

### Email

Alternatively, you can email security@symaira.com with:
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

### What to Expect

- **Acknowledgment**: We'll acknowledge receipt within 48 hours
- **Assessment**: We'll investigate and assess the severity
- **Updates**: We'll keep you informed of our progress
- **Resolution**: We'll work on a fix and coordinate disclosure

### Scope

This security policy applies to:
- The Symaira Terminal application
- The SymairaKit library
- The public repository at github.com/danieljustus/symaira-terminal

### Out of Scope

- Third-party dependencies (report to their maintainers)
- Issues in the commercial/private repository (separate contact)
- Social engineering attacks

## Security Best Practices

### For Users

- Keep your API keys in the macOS Keychain (default behavior)
- Don't share API keys in logs or screenshots
- Use environment-specific API keys when possible
- Keep the application updated

### For Contributors

- Never commit API keys or secrets
- Use environment variables for sensitive configuration
- Follow secure coding practices
- Report security issues privately first

## Disclosure Policy

We follow coordinated disclosure:
1. Reporter notifies us privately
2. We acknowledge and investigate
3. We develop a fix
4. We release the fix
5. We publicly disclose the vulnerability

Timeline: We aim to resolve critical vulnerabilities within 30 days.

## Contact

- Security email: security@symaira.com
- GitHub: [@danieljustus](https://github.com/danieljustus)
