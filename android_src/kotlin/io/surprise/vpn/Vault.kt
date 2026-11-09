package io.surprise.vpn

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Keeps secrets (configs with their passwords and keys, subscription URLs) encrypted at rest.
 * The AES-256 key lives in the Android Keystore and never leaves it; what reaches the disk is
 * AES-GCM ciphertext (12 byte IV followed by the data, Base64).
 */
object Vault {
    private const val ALIAS = "v2tun_vault"
    private const val FILE = "vault"

    private fun key(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        gen.init(
            KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
        )
        return gen.generateKey()
    }

    fun encrypt(plain: String): String {
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.ENCRYPT_MODE, key())
        val ct = c.doFinal(plain.toByteArray(Charsets.UTF_8))
        return Base64.encodeToString(c.iv + ct, Base64.NO_WRAP)
    }

    fun decrypt(blob: String): String {
        val raw = Base64.decode(blob, Base64.NO_WRAP)
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, raw, 0, 12))
        return String(c.doFinal(raw, 12, raw.size - 12), Charsets.UTF_8)
    }

    fun put(ctx: Context, name: String, value: String) {
        ctx.getSharedPreferences(FILE, Context.MODE_PRIVATE).edit().putString(name, encrypt(value)).apply()
    }

    /** The stored value, or null when there is none or it cannot be decrypted (the key was lost). */
    fun get(ctx: Context, name: String): String? {
        val blob = ctx.getSharedPreferences(FILE, Context.MODE_PRIVATE).getString(name, null) ?: return null
        return try { decrypt(blob) } catch (_: Exception) { null }
    }

    fun remove(ctx: Context, name: String) {
        ctx.getSharedPreferences(FILE, Context.MODE_PRIVATE).edit().remove(name).apply()
    }
}
