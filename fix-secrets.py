#!/usr/bin/env python3
"""
This script patches streamlitui.py to fix the SecretStr issue
when handling environment variables.
"""

import re

# Read the original file
with open('streamlitui.py', 'r') as file:
    content = file.read()

# Replace SecretStr usage with direct string references
# Pattern 1: Replace all SecretStr instances
content = re.sub(
    r'api_key=SecretStr\(([^)]+)\)', 
    r'api_key=\1', 
    content
)

# Check for commented print statements for debugging
content += """

# Add a debug block at the end of the file
if __name__ == "__main__":
    import os
    print(f"DEBUG: OPENAI_API_KEY exists: {os.environ.get('OPENAI_API_KEY') is not None}")
    print(f"DEBUG: WEAVIATE_URL exists: {os.environ.get('WEAVIATE_URL') is not None}")
    print(f"DEBUG: WEAVIATE_API_KEY exists: {os.environ.get('WEAVIATE_API_KEY') is not None}")
"""

# Write the fixed content back
with open('streamlitui.py', 'w') as file:
    file.write(content)

print("✅ Successfully patched streamlitui.py to fix SecretStr usage!") 