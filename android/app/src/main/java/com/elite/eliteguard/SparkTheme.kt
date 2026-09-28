package com.elite.eliteguard

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

// Цвета из темы Spark (spark.elitesochi.com, --portal-* и --brick).
private val SparkLight = lightColorScheme(
    primary = Color(0xFFC2452D),
    onPrimary = Color.White,
    primaryContainer = Color(0xFFF9E8E4),
    onPrimaryContainer = Color(0xFF9E3622),
    secondary = Color(0xFF787774),
    onSecondary = Color.White,
    background = Color(0xFFF8F8F7),
    onBackground = Color(0xFF18181B),
    surface = Color.White,
    onSurface = Color(0xFF18181B),
    surfaceVariant = Color(0xFFF2F1EF),
    onSurfaceVariant = Color(0xFF787774),
    outline = Color(0xFFE6E4E1),
)

private val SparkDark = darkColorScheme(
    primary = Color(0xFFD4644E),
    onPrimary = Color(0xFF101012),
    primaryContainer = Color(0xFF542B25),
    onPrimaryContainer = Color(0xFFFFDAD2),
    secondary = Color(0xFF9E9EA6),
    onSecondary = Color(0xFF101012),
    background = Color(0xFF101012),
    onBackground = Color(0xFFF4F4F5),
    surface = Color(0xFF18181A),
    onSurface = Color(0xFFF4F4F5),
    surfaceVariant = Color(0xFF212124),
    onSurfaceVariant = Color(0xFF9E9EA6),
    outline = Color(0xFF2C2C30),
)

@Composable
fun SparkTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = if (isSystemInDarkTheme()) SparkDark else SparkLight,
        content = content,
    )
}
