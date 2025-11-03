#!/usr/bin/env python3
"""
Simple Cube Root Calculator
Calculates the cube root of a given number
"""

def cube_root(number):
    """
    Calculate the cube root of a number.

    Args:
        number: The number to calculate the cube root of

    Returns:
        The cube root of the number
    """
    # Handle negative numbers by taking the cube root of the absolute value
    # and then applying the sign
    if number < 0:
        return -(abs(number) ** (1/3))
    else:
        return number ** (1/3)


def main():
    """Main function to run the cube root calculator."""
    print("=" * 40)
    print("Cube Root Calculator")
    print("=" * 40)

    try:
        # Get input from user
        user_input = input("\nEnter a number: ")
        number = float(user_input)

        # Calculate cube root
        result = cube_root(number)

        # Display result
        print(f"\nThe cube root of {number} is: {result:.6f}")

        # Verification
        print(f"Verification: {result:.6f}³ = {result**3:.6f}")

    except ValueError:
        print("Error: Please enter a valid number.")
    except KeyboardInterrupt:
        print("\n\nProgram terminated by user.")
    except Exception as e:
        print(f"An error occurred: {e}")


if __name__ == "__main__":
    main()
