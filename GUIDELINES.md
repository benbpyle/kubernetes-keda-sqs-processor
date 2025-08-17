# Junie Guidelines for SQS Processor

This document outlines the coding standards and organizational guidelines for the SQS Processor project.

## Code Style and Formatting

### Variables
- Variables must follow Rust standards
- Use snake_case for variable names, function names, and module names
- Use SCREAMING_SNAKE_CASE for constants
- Use CamelCase for types, traits, and enum variants
- Use descriptive names that clearly indicate the purpose of the variable

### Formatting
- rustfmt is the standard for formatting
- Run `cargo fmt` before committing code
- Do not override rustfmt defaults without team consensus
- Maintain a consistent 4-space indentation

## Code Organization

### Structs and Models
- Structs go in the models directory
- Each model should be in its own file
- Related models can be grouped in subdirectories
- Models should implement appropriate traits (Debug, Clone, etc.)

### AWS Operations
- AWS operations go in services directory
- Organize by AWS service (e.g., services/sqs, services/dynamodb)
- Use dependency injection for AWS clients to facilitate testing
- Implement retry logic and error handling consistently

## Testing

### Functions
- Functions must have test cases
- Use the `#[test]` attribute for unit tests
- Place tests in a `tests` module at the bottom of the file or in a separate tests directory
- Mock external dependencies when testing
- Aim for high test coverage, especially for business logic

## Documentation

- Document public APIs with rustdoc comments
- Include examples in documentation where appropriate
- Keep documentation up-to-date with code changes
- Use inline comments for complex logic

## Error Handling

- Use Result types for operations that can fail
- Provide meaningful error messages
- Consider using a custom error type for the application
- Log errors appropriately

## Dependencies

- Minimize dependencies when possible
- Keep dependencies up-to-date
- Document why each dependency is needed