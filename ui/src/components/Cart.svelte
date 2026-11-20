<script lang="ts">
import { t, language } from '@utils/i18n'

	import { CART, FURNITURE_PAYMENT_TYPES, IS_CART_OPEN } from '@store/stores'
	import { SendNUI } from '@utils/SendNUI'

	const labels: Record<string, string> = {
		money: t("Dinheiro"),
		bank: t("Banco"),
		crypto: t("Crypto"),
		coin: t("Coin"),
	}

	function paymentFor(item: any) {
		return String(item.payment || item.selectedPayment || $FURNITURE_PAYMENT_TYPES[0] || 'bank').toLowerCase()
	}

	function paymentLabel(payment: string) {
		return labels[payment] || payment.toUpperCase()
	}

	function formatValue(value: number, payment: string) {
		const formatted = Number(value || 0).toLocaleString(language, { minimumFractionDigits: 2, maximumFractionDigits: 2 })
		return payment === 'money' || payment === 'bank' ? `R$ ${formatted}` : `${formatted} ${payment.toUpperCase()}`
	}

	function selectPayment(item: any, payment: string) {
		if (item.payment) return
		const selectedPayment = String(payment).toLowerCase()
		$CART = $CART.map((entry: any) => entry.entity === item.entity ? { ...entry, selectedPayment } : entry)
		SendNUI('updateCartItem', { entity: item.entity, selectedPayment })
	}

	function removeItem(item: any) {
		SendNUI('removeCartItem', item)
	}

	$: totals = $CART.reduce((result: Record<string, number>, item: any) => {
		const payment = paymentFor(item)
		result[payment] = (result[payment] || 0) + Number(item.price || 0)
		return result
	}, {})
</script>

{#if $IS_CART_OPEN}
	<div class="cart-panel">
		<header>
			<div><h2>{t("Carrinho de móveis")}</h2><p>{t("Confira cada produto e sua forma de pagamento.")}</p></div>
			<span>{$CART.length} {t("item(ns)")}</span>
		</header>

		<div class="cart-list">
			{#each $CART as item}
				<div class="cart-item">
					<button class="item-main" on:click={() => SendNUI('selectCartItem', item)}>
						<strong>{item.label}</strong>
						<small>{formatValue(item.price, paymentFor(item))}</small>
					</button>

					<div class="payment-options" aria-label={t("Forma de pagamento")}>
						{#if item.payment}
							<button class="payment active locked" disabled title={t("Moeda definida pelo corretor")}>
								<i class="fas fa-lock" /> {paymentLabel(paymentFor(item))}
							</button>
						{:else}
							{#each $FURNITURE_PAYMENT_TYPES as payment}
								<button class:active={paymentFor(item) === payment} class="payment" on:click={() => selectPayment(item, payment)}>
									{paymentLabel(payment)}
								</button>
							{/each}
						{/if}
					</div>

					<button class="trash" title={t("Remover do carrinho")} on:click={() => removeItem(item)}><i class="fas fa-trash" /></button>
				</div>
			{/each}
			{#if $CART.length === 0}<div class="empty">{t("Seu carrinho está vazio.")}</div>{/if}
		</div>

		<div class="summary">
			<h3>{t("Resumo da cobrança")}</h3>
			{#each Object.entries(totals) as [payment, amount]}
				<div><span>{paymentLabel(payment)}</span><strong>{formatValue(amount, payment)}</strong></div>
			{/each}
		</div>

		<footer>
			<button class="back" on:click={() => ($IS_CART_OPEN = false)}><i class="fas fa-xmark" /> {t("Fechar")}</button>
			<button class="clear" disabled={$CART.length === 0} on:click={() => SendNUI('clearCartItems')}><i class="fas fa-trash" /> {t("Limpar carrinho")}</button>
			<button class="pay" disabled={$CART.length === 0} on:click={() => SendNUI('buyCartItems')}><i class="fas fa-credit-card" /> {t("Pagar")}</button>
		</footer>
	</div>
{/if}

<style>
	.cart-panel{position:absolute;right:0;top:-68rem;width:56rem;height:64rem;box-sizing:border-box;padding:2rem;background:var(--color-primary);border:1px solid rgba(255,255,255,.12);display:flex;flex-direction:column;gap:1.3rem;box-shadow:0 1.5rem 5rem rgba(0,0,0,.45)}
	header{display:flex;justify-content:space-between;align-items:center;gap:1rem}header h2{font-size:2.2rem;font-weight:700}header p{font-size:1.25rem;color:#a8b0b8;margin-top:.3rem}header>span{font-size:1.2rem;padding:.65rem .9rem;border-radius:.5rem;background:var(--color-secondary)}
	.cart-list{display:flex;flex-direction:column;gap:.8rem;overflow-y:auto;min-height:0;flex:1;padding-right:.4rem}.cart-item{display:grid;grid-template-columns:minmax(13rem,1fr) minmax(20rem,auto) 4rem;align-items:center;gap:.8rem;min-height:7rem;padding:.8rem;background:var(--color-secondary);border:1px solid rgba(255,255,255,.08)}
	.item-main{text-align:left;min-width:0;padding:.5rem}.item-main strong,.item-main small{display:block;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.item-main strong{font-size:1.55rem}.item-main small{font-size:1.25rem;color:var(--color-accent);margin-top:.45rem;font-weight:700}
	.payment-options{display:flex;justify-content:flex-end;flex-wrap:wrap;gap:.45rem}.payment{font-size:1.05rem;padding:.55rem .7rem;border:1px solid rgba(255,255,255,.18);border-radius:.45rem;background:rgba(0,0,0,.2);color:#b9c0c7}.payment:hover,.payment.active{border-color:var(--color-accent);color:#fff;background:color-mix(in srgb,var(--color-accent) 24%,transparent)}.payment.locked{cursor:not-allowed;opacity:1}.payment i{margin-right:.35rem}
	.trash{height:4rem;width:4rem;background:#491f26;color:#ff6674;border-radius:.45rem}.trash:hover{background:#7a2632}.empty{display:grid;place-items:center;min-height:14rem;color:#a8b0b8;font-size:1.4rem}
	.summary{padding:1rem 1.2rem;background:rgba(0,0,0,.22);border:1px solid rgba(255,255,255,.1)}.summary h3{font-size:1.35rem;margin-bottom:.65rem}.summary>div{display:flex;justify-content:space-between;font-size:1.25rem;padding:.3rem 0}.summary strong{color:var(--color-accent)}
	footer{display:grid;grid-template-columns:auto 1fr 1fr;gap:.7rem}footer button{min-height:4.8rem;padding:0 1.2rem;font-size:1.25rem;font-weight:700}footer button:disabled{opacity:.4;cursor:not-allowed}.back{background:var(--color-secondary)}.clear{background:#56232b;color:#ff9aa3}.pay{background:var(--color-accent);color:#fff}
</style>