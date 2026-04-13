"""
Logger - Logare cu Rich pentru output frumos in terminal.
"""

import sys
from loguru import logger

# Configureaza loguru cu format frumos
logger.remove()
logger.add(
    sys.stdout,
    format="<green>{time:HH:mm:ss}</green> | <level>{level: <8}</level> | <cyan>{name}</cyan> - <level>{message}</level>",
    level="DEBUG",
    colorize=True,
)
logger.add(
    "logs/bot_{time:YYYY-MM-DD}.log",
    format="{time:YYYY-MM-DD HH:mm:ss} | {level: <8} | {name} - {message}",
    level="DEBUG",
    rotation="1 day",
    retention="7 days",
)

log = logger
