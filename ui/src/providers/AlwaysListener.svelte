<script lang="ts">
import { t } from '@utils/i18n'

	import { ReceiveNUI } from '@utils/ReceiveNUI'
	import { debugData } from '@utils/debugData'
	import { FURNITURES, SHOWFURNITURES, browserMode, visibility, CART, IS_MENU_MINIMIZED, OWNEDITEMS, CURRENTFURNITURE, FURNITURE_PAYMENT_TYPES } from '@store/stores'
	import ModelStore from '@store/ModelStore'
	import ItemList from '@components/ItemList.svelte'




	debugData([
		{
			action: 'setVisible',
			data: true,
		},
	])

	debugData([
		{
			action: 'setBrowserMode',
			data: true
		},
	])

	function browserHideAndShow(e: KeyboardEvent) {
		if (e.key === '=') {
			$visibility = true
		}
	}

	ReceiveNUI('setBrowserMode', (data: boolean) => {
		browserMode.set(data)
		console.log(t("browser mode enabled"))
		if (data) {
			window.addEventListener('keydown', browserHideAndShow)
		} else {
			window.removeEventListener('keydown', browserHideAndShow)
		}
	})


	// MODELR STUFF
	ReceiveNUI('setupModel', (data: any) => {
		ModelStore.show.set(true)
		ModelStore.setupModel(data)
	})

	ReceiveNUI('updateCamera', (data: any) => {
		ModelStore.updateCamera(data)
	})




	// FURNITURES STUFF

	ReceiveNUI('setFurnituresData', (data: any) => {
		const categories = Array.isArray(data)
			? data
				.filter((category: any) => category && Array.isArray(category.items))
				.map((category: any) => ({
					...category,
					category: category.category ?? category.label ?? category.id ?? t("Sem categoria")
				}))
			: []
		FURNITURES.set(categories)
		SHOWFURNITURES.set(categories[0] ?? { category: '', items: [] })
	})


	ReceiveNUI('setFurniturePaymentTypes', (data: any) => {
		const payments = Array.isArray(data) ? data.map((value: any) => String(value).toLowerCase()).filter(Boolean) : []
		$FURNITURE_PAYMENT_TYPES = payments.length ? payments : ['bank', 'money']
	})

	// Cart Stuff
	
	ReceiveNUI('addToCart', (cartEntry: any) => {
		$CART = [...$CART, cartEntry]
		ModelStore.show.set(false)
		$IS_MENU_MINIMIZED = false
	})

	ReceiveNUI('removeFromCart', (data: any) => {
		// This code removes a product from the cart
		// The product is identified by the entity ID
		// The code is used in the removeFromCart function

		$CART = $CART.filter((entry: any) => entry.entity != data.entity)
		$CART = [...$CART]
		$CURRENTFURNITURE = null
		ModelStore.show.set(false)
	})

	ReceiveNUI('updateCartItem', (data:any) => {$CART=$CART.map(item=>item.entity===data.entity?data:item)})

	ReceiveNUI('clearCart', () => {
		$CART = []
	})

	ReceiveNUI("setOwnedItems", (data: any) => {
		$OWNEDITEMS = Array.isArray(data) ? data.filter(Boolean) : []
	})

	ReceiveNUI("removeOwnedItem", (data: any) => {
		let newItems = $OWNEDITEMS.filter((entry: any) => entry.id != data.id)
		$OWNEDITEMS = [...newItems]
	})


</script>
